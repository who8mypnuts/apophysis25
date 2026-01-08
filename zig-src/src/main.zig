const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const flame = @import("flame.zig");
const colors = @import("colors.zig");
const renderer = @import("renderer.zig");
const io = @import("io.zig");
const gradient_browser = @import("gradient_browser.zig");

// Coordinate conversion helpers
fn toScreen(wx: f32, wy: f32, zoom: f32, width: f32, height: f32) rl.Vector2 {
    const cx = width / 2.0;
    const cy = height / 2.0;
    return rl.Vector2{
        .x = (wx * zoom) + cx,
        .y = cy - (wy * zoom),
    };
}

fn toWorld(sx: f32, sy: f32, zoom: f32, width: f32, height: f32) rl.Vector2 {
    const cx = width / 2.0;
    const cy = height / 2.0;
    return rl.Vector2{
        .x = (sx - cx) / zoom,
        .y = (cy - sy) / zoom,
    };
}

fn rlToFlameColor(c: rl.Color) colors.Color {
    return .{
        .r = @as(f32, @floatFromInt(c.r)) / 255.0,
        .g = @as(f32, @floatFromInt(c.g)) / 255.0,
        .b = @as(f32, @floatFromInt(c.b)) / 255.0,
    };
}

fn flameToRlColor(c: colors.Color) rl.Color {
    return rl.Color.init(
        @as(u8, @intFromFloat(@max(0.0, @min(1.0, c.r)) * 255.0)),
        @as(u8, @intFromFloat(@max(0.0, @min(1.0, c.g)) * 255.0)),
        @as(u8, @intFromFloat(@max(0.0, @min(1.0, c.b)) * 255.0)),
        255,
    );
}

pub fn drawFloatControl(
    bounds: rl.Rectangle,
    text: [:0]const u8,
    value: *f32,
    min: f32,
    max: f32,
    active_id: *i32,
    this_id: i32,
    shared_buffer: []u8
) void {
    const sliderWidth: f32 = bounds.width - 70.0;
    const boxWidth: f32 = 65.0;
    
    // Draw Label (above or left? The passed bounds are for the control area)
    // The previous code had separate label calls.
    // Let's assume this function handles the slider + box part, and label is drawn separately or passed in 'text'.
    // Existing code: Label line, then Slider line.
    // This function will draw: [Slider --] [Box]
    // The label "text" is for the slider (usually left of it or inside).
    // Let's make it compact.
    
    const sliderBounds = rl.Rectangle.init(bounds.x, bounds.y, sliderWidth, bounds.height);
    const boxBounds = rl.Rectangle.init(bounds.x + sliderWidth + 5.0, bounds.y, boxWidth, bounds.height);

    _ = rg.slider(sliderBounds, text, "", value, min, max);

    const is_editing = (active_id.* == this_id);
    
    // Bounds for the value box already declared above at line 67

    if (is_editing) {
        // Edit Mode: Draw TextBox
        // Prepare buffer slice
        shared_buffer[shared_buffer.len-1] = 0;
        const buf_ptr = shared_buffer[0 .. shared_buffer.len-1 :0];
        
        // TextBox returns true if ENTER is pressed
        if (rg.textBox(boxBounds, buf_ptr, 32, true)) {
            // Apply changes
            // Parse float
             const parsed = std.fmt.parseFloat(f32, std.mem.sliceTo(shared_buffer, 0)) catch null;
             if (parsed) |v| {
                 value.* = v;
             }
             active_id.* = -1;
        }
        
        // Optional: Check for click outside to commit/cancel?
        // Raygui keeps focus usually until Enter or click elsewhere. 
        // If we click another control, `active_id` changes in that control's logic?
        // No, we need to detect clicks outside.
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
             const mouse = rl.getMousePosition();
             if (!rl.checkCollisionPointRec(mouse, boxBounds)) {
                 // Clicked outside: Commit and close
                 const parsed = std.fmt.parseFloat(f32, std.mem.sliceTo(shared_buffer, 0)) catch null;
                 if (parsed) |v| {
                     value.* = v;
                 }
                 active_id.* = -1;
             }
        }
    } else {
        // Display Mode: Draw ValueBox (static)
        var temp_buf: [32]u8 = undefined;
        const buf_ptr = std.fmt.bufPrintZ(&temp_buf, "{d:.3}", .{value.*}) catch blk: {
            temp_buf[0] = 0;
            break :blk temp_buf[0..0 :0];
        };
        
        // Use valueBox in non-edit mode just for display style
        // We pass 'false' for editMode.
        var dummy_val: c_int = 0;
        _ = rg.valueBox(boxBounds, "", &dummy_val, 0, 0, false);
        // Overwrite text with float string manually because valueBox takes int*
        // Actually, let's just use `guiLabel` or `guiTextBox(..., false)` (read only)
        // `valueBoxFloat` (false) works for display? The user said "cannot type".
        // Let's use `textBox` (edit=false) to show the number.
        _ = rg.textBox(boxBounds, buf_ptr, 32, false);
        
        // Manual Click Detection to Enter Edit Mode
        const mouse_pos = rl.getMousePosition();
        if (rl.checkCollisionPointRec(mouse_pos, boxBounds) and rl.isMouseButtonPressed(rl.MouseButton.left)) {
             active_id.* = this_id;
             // Seed the buffer for editing
             _ = std.fmt.bufPrintZ(shared_buffer, "{d}", .{value.*}) catch {}; 
             // Use plain {d} for editing to avoid trailing zeros if possible, or {d:.3} if preferred.
             // {d} preserves precision better for re-parsing.
        }
    }
}

pub fn main() anyerror!void {
    const screenWidth = 1400;
    const screenHeight = 900;

    rl.initWindow(screenWidth, screenHeight, "Apophysis Zig");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // GUI State
    var iterations_per_frame: f32 = 10000.0;
    var zoom: f32 = 50.0;
    var gamma: f32 = 2.2;
    var brightness: f32 = 1.0;
    var vibrancy: f32 = 1.0;
    
    var selected_xform: i32 = 0;
    var active_edit_id: i32 = -1; // -1 means no active edit
    var edit_buffer: [32]u8 = undefined; // Shared buffer for text editing

    // Menu State
    const MENU_HEIGHT: f32 = 24.0;
    var file_menu_open: bool = false;
    var edit_menu_open: bool = false;
    // var show_about_box: bool = false; // Future use?

    // Editor Tab State
    var active_tab: enum { Fractal, Transform, Color } = .Fractal;
    var xform_dropdown_edit_mode: bool = false;
    var selected_color_node: i32 = 0;
    var picker_color_rl: rl.Color = rl.Color.white;
    // Smart Sync State
    var last_color_node_idx: i32 = -1;
    var last_history_idx: usize = 0;

    
    // Triangle Editor State
    var drag_mode: enum { None, DragO, DragX, DragY, DragScale, DragRotate } = .None;
    var drag_start_mouse: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 };
    var drag_start_val: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 }; // Stores original O, X, or Y world pos
    var move_step: f32 = 0.1;
    var show_grid: bool = false;
    

    
    // For scale drag, store original coefficients
    var drag_original_a: f32 = 0;
    var drag_original_b: f32 = 0;
    var drag_original_c: f32 = 0;
    var drag_original_d: f32 = 0;
    
    // History System
    const UndoStack = struct {
        items: std.ArrayList(flame.Flame),
        current_idx: usize,
        allocator: std.mem.Allocator,
        
        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .items = .{},
                .current_idx = 0,
                .allocator = allocator,
            };
        }
        
        fn deinit(self: *@This()) void {
            for (self.items.items) |*item| {
                self.allocator.free(item.xforms);
            }
            self.items.deinit(self.allocator);
        }
        
        fn push(self: *@This(), f: flame.Flame) !void {
            // Remove any redo history
            while (self.items.items.len > self.current_idx) {
                const popped = self.items.pop() orelse break;
                self.allocator.free(popped.xforms);
            }
            
            // Clone the flame
            const xforms_copy = try self.allocator.alloc(flame.Xform, f.xforms.len);
            @memcpy(xforms_copy, f.xforms);
            
            const f_copy = flame.Flame{
                .xforms = xforms_copy,
                .palette = f.palette,
                .gamma = f.gamma,
                .brightness = f.brightness,
                .vibrancy = f.vibrancy,
            };
            
            try self.items.append(self.allocator, f_copy);
            self.current_idx = self.items.items.len;
        }
        
        fn canUndo(self: *const @This()) bool {
            return self.current_idx > 1;
        }
        
        fn canRedo(self: *const @This()) bool {
            return self.current_idx < self.items.items.len;
        }
        
        fn undo(self: *@This()) ?flame.Flame {
            if (!self.canUndo()) return null;
            self.current_idx -= 1;
            return self.items.items[self.current_idx - 1];
        }
        
        fn redo(self: *@This()) ?flame.Flame {
            if (!self.canRedo()) return null;
            const result = self.items.items[self.current_idx];
            self.current_idx += 1;
            return result;
        }
    };
    
    var allocator = std.heap.page_allocator;
    
    // Initialize Gradient Browser library
    var gradient_library = gradient_browser.GradientLibrary.init(allocator);
    defer gradient_library.deinit();

    // Try to load default gradients if they exist
    gradient_library.loadFromFile("ag7.ugr") catch {
        // It's OK if file doesn't exist yet
    };
    
    // Gradient Browser UI state
    var show_gradient_browser: bool = false;
    var gradient_browser_selected: ?usize = null;
    var gradient_file_path_buf: [256:0]u8 = undefined;
    @memset(gradient_file_path_buf[0..], 0);
    @memcpy(gradient_file_path_buf[0..7], "ag7.ugr");
    var gradient_browser_scroll: f32 = 0.0;
    var gradient_context_menu_open: bool = false;
    var gradient_context_menu_pos: rl.Vector2 = undefined;
    var gradient_context_menu_idx: usize = 0;
    var gradient_clipboard: ?gradient_browser.GradientEntry = null;
    defer if (gradient_clipboard) |*cp| cp.deinit(allocator);
    
    var history = UndoStack.init(allocator);
    defer history.deinit();
    
    var initial_xforms = try allocator.alloc(flame.Xform, 3);
    initial_xforms[0] = flame.Xform{ .a = 0.5, .d = 0.5, .e = 0.0, .f = 0.0, .swirl = 1.0, .color = 0.0 };
    initial_xforms[1] = flame.Xform{ .a = 0.5, .d = 0.5, .e = 0.5, .f = 0.0, .horseshoe = 1.0, .color = 0.5 };
    initial_xforms[2] = flame.Xform{ .a = 0.5, .d = 0.5, .e = 0.25, .f = 0.433, .linear = 1.0, .color = 1.0 };

    var f = flame.Flame{
        .xforms = initial_xforms,
        .palette = colors.Palette.initDefault(),
        .gamma = 2.2,
        .brightness = 1.0,
        .vibrancy = 1.0,
    };

    // Push initial state to history
    try history.push(f);

    // Render area
    const renderWidth = 800; // Left side
    const renderHeight = 900;

    // Renderer state
    var render_state = try renderer.RenderState.init(std.heap.page_allocator, renderWidth, renderHeight);
    defer render_state.deinit();
    render_state.upload_palette(f.palette.colors[0..]);

    // Texture for displaying the buffer
    const image = rl.genImageColor(renderWidth, renderHeight, rl.Color.black);
    // We need to keep the texture alive
    const texture = try rl.loadTextureFromImage(image);
    // Unload image data, we will update texture directly from our buffer
    rl.unloadImage(image); 

    // Pixel buffer for Raylib
    const pixel_buffer = try std.heap.page_allocator.alloc(u8, @as(usize, renderWidth * renderHeight * 4));
    defer std.heap.page_allocator.free(pixel_buffer);

    while (!rl.windowShouldClose()) {
        // Update
        render_state.scale = zoom;
        render_state.gamma = gamma;
        render_state.brightness = brightness;
        render_state.vibrancy = vibrancy;
        
        render_state.render_iterations(f, @as(usize, @intFromFloat(iterations_per_frame)));

        // Update texture
        // TODO: Update renderer settings like zoom
        // render_state.zoom = zoom; 

        if (render_state.gpu_enabled) {
            render_state.update_and_draw_gpu();
        } else {
            render_state.get_texture_data(pixel_buffer);
            rl.updateTexture(texture, pixel_buffer.ptr);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.fromInt(0x181818FF)); // Dark gray background
        
        // Draw the accumulator texture
        if (render_state.gpu_enabled) {
            // Draw result from GPU (note: RT textures are upside down)
            const source = rl.Rectangle.init(0, 0, @floatFromInt(renderWidth), @floatFromInt(-renderHeight));
            const dest = rl.Rectangle.init(0, MENU_HEIGHT, @floatFromInt(renderWidth), @floatFromInt(renderHeight));
            rl.drawTexturePro(render_state.render_texture.texture, source, dest, rl.Vector2.init(0,0), 0.0, rl.Color.white);
        } else {
            rl.drawTexture(texture, 0, @intFromFloat(MENU_HEIGHT), rl.Color.white);
        }

        // Draw Grid if enabled
        if (show_grid) {
             const center_x = @as(f32, @floatFromInt(renderWidth)) / 2.0;
             const center_y = @as(f32, @floatFromInt(renderHeight)) / 2.0;
             const grid_color = rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 };
             const axis_color = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
             
             // Calculate visible world bounds
             const min_x_world = (0.0 - center_x) / zoom;
             const max_x_world = (@as(f32, @floatFromInt(renderWidth)) - center_x) / zoom;
             const min_y_world = (0.0 - center_y) / zoom;
             const max_y_world = (@as(f32, @floatFromInt(renderHeight)) - center_y) / zoom;
             
             const grid_step: f32 = 0.5;
             
             // Draw vertical lines
             var gx = @floor(min_x_world / grid_step) * grid_step;
             while (gx <= max_x_world) : (gx += grid_step) {
                 const sx = center_x + gx * zoom;
                 const color = if (@abs(gx) < 0.001) axis_color else grid_color;
                 rl.drawLine(@as(i32, @intFromFloat(sx)), @as(i32, @intFromFloat(MENU_HEIGHT)), @as(i32, @intFromFloat(sx)), @as(i32, @intFromFloat(MENU_HEIGHT)) + renderHeight, color);
             }
             
             // Draw horizontal lines (Y increases downward in screen space, upward in world space)
             var gy = @floor(min_y_world / grid_step) * grid_step;
             while (gy <= max_y_world) : (gy += grid_step) {
                 const sy = center_y - gy * zoom; // Minus because Y axis is flipped
                 const color = if (@abs(gy) < 0.001) axis_color else grid_color;
                 rl.drawLine(0, @as(i32, @intFromFloat(MENU_HEIGHT + sy)), renderWidth, @as(i32, @intFromFloat(MENU_HEIGHT + sy)), color);
             }
        }

        // --- Triangle Editor Overlay ---
        const rWidthF = @as(f32, @floatFromInt(renderWidth));
        const rHeightF = @as(f32, @floatFromInt(renderHeight));
        var mouse_pos = rl.getMousePosition();
        
        // Adjust mouse for menu offset
        mouse_pos.y -= MENU_HEIGHT;
        
        
        const raw_mouse = rl.getMousePosition();
        const mouse_on_menu = (raw_mouse.y < MENU_HEIGHT);
        
        // Only block if mouse is in menu bar OR in an open menu dropdown area OR modal is open
        var input_blocked = mouse_on_menu or show_gradient_browser;
        if (file_menu_open and raw_mouse.y < MENU_HEIGHT + 24.0 * 3.0 and raw_mouse.x < 120.0) {
            input_blocked = true;
        }
        if (edit_menu_open and raw_mouse.y < MENU_HEIGHT + 24.0 * 4.0 and raw_mouse.x >= 60 and raw_mouse.x < 60 + 170.0) {
            input_blocked = true;
        }
        
        // Mouse wheel zoom (when not over menu or GUI panel)
        if (!input_blocked and raw_mouse.x < renderWidth) {
            const wheel = rl.getMouseWheelMove();
            if (wheel != 0) {
                // Zoom in/out: wheel up = zoom in, wheel down = zoom out
                zoom += wheel * 5.0; // 5 units per wheel notch
                zoom = @max(10.0, @min(500.0, zoom)); // Clamp zoom range
                render_state.reset_histogram();
            }
        }
        
        
        
        // Keyboard Shortcuts
        // Undo: Ctrl + Z
        const ctrl_pressed = rl.isKeyDown(rl.KeyboardKey.left_control) or rl.isKeyDown(rl.KeyboardKey.right_control);
        const shift_pressed = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift);
        
        if (ctrl_pressed and rl.isKeyPressed(rl.KeyboardKey.z)) {
            if (shift_pressed) {
                // Ctrl + Shift + Z -> Redo
                 if (history.redo()) |restored| {
                    // Reallocate if length changed
                    if (f.xforms.len != restored.xforms.len) {
                        if (allocator.realloc(f.xforms, restored.xforms.len)) |new_ptr| {
                            f.xforms = new_ptr;
                        } else |_| {
                            // Alloc failed, abort redo for now
                            _ = history.undo(); // Revert internal index? actually undo() moves idx back. 
                            // This is tricky. simpler to just not copy if alloc failed.
                            // But we already advanced history index.
                        }
                    }

                    if (f.xforms.len == restored.xforms.len) {
                        @memcpy(f.xforms, restored.xforms);
                        f.palette = restored.palette;
                        f.gamma = restored.gamma;
                        f.brightness = restored.brightness;
                        f.vibrancy = restored.vibrancy;
                        render_state.reset_histogram();
                        
                        gamma = f.gamma;
                        brightness = f.brightness;
                        vibrancy = f.vibrancy;
                        
                        // Fix selection if out of bounds
                        if (selected_xform >= f.xforms.len) {
                            selected_xform = @as(i32, @intCast(f.xforms.len - 1));
                        }
                    }
                }
            } else {
                // Ctrl + Z -> Undo
                if (history.undo()) |restored| {
                    // Reallocate if length changed
                    if (f.xforms.len != restored.xforms.len) {
                        if (allocator.realloc(f.xforms, restored.xforms.len)) |new_ptr| {
                            f.xforms = new_ptr;
                        } else |_| {
                             // Alloc failed
                        }
                    }

                    if (f.xforms.len == restored.xforms.len) {
                        @memcpy(f.xforms, restored.xforms);
                        f.palette = restored.palette;
                        f.gamma = restored.gamma;
                        f.brightness = restored.brightness;
                        f.vibrancy = restored.vibrancy;
                        render_state.reset_histogram();
                        
                        gamma = f.gamma;
                        brightness = f.brightness;
                        vibrancy = f.vibrancy;

                        // Fix selection if out of bounds
                        if (selected_xform >= f.xforms.len) {
                            selected_xform = @as(i32, @intCast(f.xforms.len - 1));
                        }
                    }
                }
            }
        }
        
        // Ctrl + Y -> Redo
        if (ctrl_pressed and rl.isKeyPressed(rl.KeyboardKey.y)) {
             if (history.redo()) |restored| {
                // Reallocate if length changed
                if (f.xforms.len != restored.xforms.len) {
                    if (allocator.realloc(f.xforms, restored.xforms.len)) |new_ptr| {
                        f.xforms = new_ptr;
                    } else |_| {
                         // Alloc failed
                    }
                }

                if (f.xforms.len == restored.xforms.len) {
                    @memcpy(f.xforms, restored.xforms);
                    f.palette = restored.palette;
                    f.gamma = restored.gamma;
                    f.brightness = restored.brightness;
                    f.vibrancy = restored.vibrancy;
                    render_state.reset_histogram();
                    
                    gamma = f.gamma;
                    brightness = f.brightness;
                    vibrancy = f.vibrancy;
                    
                    // Fix selection if out of bounds
                    if (selected_xform >= f.xforms.len) {
                        selected_xform = @as(i32, @intCast(f.xforms.len - 1));
                    }
                }
            }
        }

        // Input Handling - Mouse Press (only when not blocked AND inside viewport)
        if (!input_blocked and raw_mouse.x < renderWidth and selected_xform >= 0 and selected_xform < f.xforms.len) {
             const idx = @as(usize, @intCast(selected_xform));
             const xf = &f.xforms[idx];
             
             // Calculate Screen Points
             const O = toScreen(xf.e, xf.f, zoom, rWidthF, rHeightF);
             const X = toScreen(xf.a + xf.e, xf.b + xf.f, zoom, rWidthF, rHeightF);
             const Y = toScreen(xf.c + xf.e, xf.d + xf.f, zoom, rWidthF, rHeightF);

             // Interaction - only start drag when not blocked
             if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                 // Check hits (simple circle distance)
                 const hit_dist = 10.0;
                 // Helper for distance squared
                 const d2 = struct {
                     fn dist2(v1: rl.Vector2, v2: rl.Vector2) f32 {
                         const dx = v1.x - v2.x;
                         const dy = v1.y - v2.y;
                         return dx*dx + dy*dy;
                     }
                 }.dist2;
                 
                 if (d2(mouse_pos, O) < hit_dist * hit_dist) {
                     drag_mode = .DragO;
                     drag_start_mouse = mouse_pos;
                     drag_start_val = rl.Vector2{ .x = xf.e, .y = xf.f };
                 } else if (d2(mouse_pos, X) < hit_dist * hit_dist) {
                     drag_mode = .DragX;
                     drag_start_mouse = mouse_pos;
                     drag_start_val = rl.Vector2{ .x = xf.a, .y = xf.b };
                 } else if (d2(mouse_pos, Y) < hit_dist * hit_dist) {
                     drag_mode = .DragY;
                     drag_start_mouse = mouse_pos;
                     drag_start_val = rl.Vector2{ .x = xf.c, .y = xf.d };
                 } else {
                     // Check if clicking on X-Y line for scale drag
                     // Calculate perpendicular distance from mouse to line segment X-Y
                     const line_dx = Y.x - X.x;
                     const line_dy = Y.y - X.y;
                     const line_len_sq = line_dx * line_dx + line_dy * line_dy;
                     
                     if (line_len_sq > 0.0001) { // Avoid division by zero
                         // Project mouse onto line
                         const t = @max(0.0, @min(1.0, 
                             ((mouse_pos.x - X.x) * line_dx + (mouse_pos.y - X.y) * line_dy) / line_len_sq
                         ));
                         
                         const proj_x = X.x + t * line_dx;
                         const proj_y = X.y + t * line_dy;
                         const dist_sq = (mouse_pos.x - proj_x) * (mouse_pos.x - proj_x) + 
                                        (mouse_pos.y - proj_y) * (mouse_pos.y - proj_y);
                         
                     if (dist_sq < hit_dist * hit_dist) {
                         drag_mode = .DragScale;
                         drag_start_mouse = mouse_pos;
                         // Store original coefficients for absolute scaling
                         drag_original_a = xf.a;
                         drag_original_b = xf.b;
                         drag_original_c = xf.c;
                         drag_original_d = xf.d;
                     } else {
                         // Background Click -> Rotate
                         drag_mode = .DragRotate;
                         drag_start_mouse = mouse_pos;
                         // Store original coefficients for absolute rotation
                         drag_original_a = xf.a;
                         drag_original_b = xf.b;
                         drag_original_c = xf.c;
                         drag_original_d = xf.d;
                     }
                 } else {
                     // Line too short, treat as background
                     drag_mode = .DragRotate;
                     drag_start_mouse = mouse_pos;
                     drag_original_a = xf.a;
                     drag_original_b = xf.b;
                     drag_original_c = xf.c;
                     drag_original_d = xf.d;
                 }
             }
             }
        }
        
        // Mouse Release - always check if we're dragging
        if (rl.isMouseButtonReleased(rl.MouseButton.left) or rl.isMouseButtonReleased(rl.MouseButton.right)) {
            if (drag_mode != .None) {
                // Push to history when we finish dragging
                history.push(f) catch |err| {
                    std.debug.print("Failed to push history: {}\n", .{err});
                };
            }
            drag_mode = .None;
        }

        // Drag Update - always update if dragging
        if (drag_mode != .None and selected_xform >= 0 and selected_xform < f.xforms.len) {
            const idx = @as(usize, @intCast(selected_xform));
            var xf = &f.xforms[idx];
            
            // Calculate Delta in World Space
            const mw = toWorld(mouse_pos.x, mouse_pos.y, zoom, rWidthF, rHeightF);
            const smw = toWorld(drag_start_mouse.x, drag_start_mouse.y, zoom, rWidthF, rHeightF);
            
            const dx = mw.x - smw.x;
            const dy = mw.y - smw.y;

            switch (drag_mode) {
                .DragO => {
                    xf.e = drag_start_val.x + dx;
                    xf.f = drag_start_val.y + dy;
                },
                .DragX => {
                    xf.a = drag_start_val.x + dx;
                    xf.b = drag_start_val.y + dy;
                },
                .DragY => {
                    xf.c = drag_start_val.x + dx;
                    xf.d = drag_start_val.y + dy;
                },
                .DragScale => {
                    // Calculate absolute scale based on total vertical movement from start
                    // Drag up = bigger (negative screen dy), drag down = smaller (positive screen dy)
                    const total_dy = drag_start_mouse.y - mouse_pos.y; // Inverted: up is positive
                    const scale_factor = 1.0 + (total_dy * 0.005); // 0.5% per pixel
                    const clamped_scale = @max(0.1, @min(10.0, scale_factor));
                    
                    // Apply absolute scale to original coefficients
                    xf.a = drag_original_a * clamped_scale;
                    xf.b = drag_original_b * clamped_scale;
                    xf.c = drag_original_c * clamped_scale;
                    xf.d = drag_original_d * clamped_scale;
                },
                .DragRotate => {
                    // Drag Right = Clockwise (+ angle)
                    // Drag Left = Counter-Clockwise (- angle)
                    const total_dx = mouse_pos.x - drag_start_mouse.x;
                    const angle_delta = total_dx * 1.0; // 1 degree per pixel

                    // Reset to original
                    xf.a = drag_original_a;
                    xf.b = drag_original_b;
                    xf.c = drag_original_c;
                    xf.d = drag_original_d;
                    
                    // Apply rotation
                    xf.rotate(angle_delta);
                },
                .None => {},
            }
            
            // Reset histogram on change
            render_state.reset_histogram();
        }
        
        for (f.xforms, 0..) |xf, i| {
            const is_selected = (i == @as(usize, @intCast(selected_xform)));
            const color = if (is_selected) rl.Color.red else rl.Color.gray;
            const alpha: u8 = if (is_selected) 255 else 100;
            const draw_color = rl.Color.init(color.r, color.g, color.b, alpha);
            
            // Triangle Points
            // Origin (e, f)
            const O = toScreen(xf.e, xf.f, zoom, rWidthF, rHeightF);
            // X-Tip (a+e, b+f)
            const X = toScreen(xf.a + xf.e, xf.b + xf.f, zoom, rWidthF, rHeightF);
            // Y-Tip (c+e, d+f)
            const Y = toScreen(xf.c + xf.e, xf.d + xf.f, zoom, rWidthF, rHeightF);
            
            // Adjust for menu offset when drawing
            var O_draw = O;
            var X_draw = X;
            var Y_draw = Y;
            O_draw.y += MENU_HEIGHT;
            X_draw.y += MENU_HEIGHT;
            Y_draw.y += MENU_HEIGHT;
            
            // Draw Axis Lines
            rl.drawLineEx(O_draw, X_draw, 2.0, draw_color);
            rl.drawLineEx(O_draw, Y_draw, 2.0, draw_color);
            
            // Draw Triangle Connection (optional, helps see the shape)
            rl.drawLineEx(X_draw, Y_draw, 1.0, rl.Color.init(draw_color.r, draw_color.g, draw_color.b, @divTrunc(alpha, 2)));

            // Draw Points
            rl.drawCircleV(O_draw, 4.0, draw_color); // Origin
            rl.drawCircleV(X_draw, 3.0, draw_color); // X
            rl.drawCircleV(Y_draw, 3.0, draw_color); // Y
            
            if (is_selected) {
                 rl.drawText("O", @as(i32, @intFromFloat(O_draw.x)) + 5, @as(i32, @intFromFloat(O_draw.y)) + 5, 10, rl.Color.white);
                 rl.drawText("X", @as(i32, @intFromFloat(X_draw.x)) + 5, @as(i32, @intFromFloat(X_draw.y)) + 5, 10, rl.Color.white);
            }
        }

        // Draw GUI Panel
        // Grid Checkbox
        _ = rg.checkBox(rl.Rectangle.init(renderWidth - 60, renderHeight - 30, 15, 15), "Grid", &show_grid);

        // Sidebar
        const guiWidth = screenWidth - renderWidth;
        rl.drawRectangle(@intFromFloat(renderWidth), 0, guiWidth, screenHeight, rl.Color.light_gray);
        _ = rg.panel(rl.Rectangle.init(renderWidth, 0, @floatFromInt(guiWidth), @as(f32, @floatFromInt(screenHeight))), "Editor Controls");
        
        // Vertical tabs on left side
        const tabWidth: f32 = 90.0;
        const tabHeight: f32 = 40.0;
        const panelX: f32 = @floatFromInt(renderWidth);
        var tabY: f32 = MENU_HEIGHT + 10.0;
        
        // Fractal tab
        const fractal_active = (active_tab == .Fractal);
        const fractal_text = if (fractal_active) "#Fractal#" else "Fractal";
        if (rg.button(rl.Rectangle.init(panelX + 5, tabY, tabWidth, tabHeight), fractal_text)) {
            active_tab = .Fractal;
            xform_dropdown_edit_mode = false;
        }
        tabY += tabHeight + 5;
        
        // Transform tab
        const transform_active = (active_tab == .Transform);
        const transform_text = if (transform_active) "#Transform#" else "Transform";
        if (rg.button(rl.Rectangle.init(panelX + 5, tabY, tabWidth, tabHeight), transform_text)) {
            active_tab = .Transform;
            xform_dropdown_edit_mode = false;
        }
        
        // Color tab
        tabY += tabHeight + 5;
        const color_active = (active_tab == .Color);
        const color_text = if (color_active) "#Color#" else "Color";
        if (rg.button(rl.Rectangle.init(panelX + 5, tabY, tabWidth, tabHeight), color_text)) {
            active_tab = .Color;
            xform_dropdown_edit_mode = false;
        }
        
        // Content area (to the right of tabs)
        // Increased space for labels
        const contentX: f32 = panelX + tabWidth + 110.0;
        var cy: f32 = MENU_HEIGHT + 20.0;
        var global_control_id: i32 = 1000;
        
        // Draw content based on active tab
        switch (active_tab) {
            .Fractal => {
                // Global fractal settings
                _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Fractal Settings");
                cy += 30;
                
                global_control_id += 1;
                drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Iterations/Frame", &iterations_per_frame, 1000, 100000, &active_edit_id, global_control_id, &edit_buffer);
                cy += 40;

                global_control_id += 1;
                drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Zoom", &zoom, 10, 200, &active_edit_id, global_control_id, &edit_buffer);
                cy += 40;

                global_control_id += 1;
                drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Gamma", &gamma, 0.1, 5.0, &active_edit_id, global_control_id, &edit_buffer);
                cy += 40;

                global_control_id += 1;
                drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Brightness", &brightness, 0.1, 10.0, &active_edit_id, global_control_id, &edit_buffer);
                cy += 40;

                global_control_id += 1;
                drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Vibrancy", &vibrancy, 0.0, 2.0, &active_edit_id, global_control_id, &edit_buffer);
                cy += 40;

                _ = rg.checkBox(rl.Rectangle.init(contentX, cy, 20, 20), "GPU Enabled", &render_state.gpu_enabled);
                cy += 30;

                if (rg.button(rl.Rectangle.init(contentX, cy, 150, 30), "Reset Histogram")) {
                    render_state.reset_histogram();
                }
            },
            .Transform => {
                // Transform editor
                _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Transform Editor");
                cy += 25;
                
                // Construct dropdown string: "T0;T1;T2..."
                var xform_list_str: [512]u8 = undefined;
                var list_offset: usize = 0;
                for (f.xforms, 0..) |_, i| {
                    if (i > 0) {
                        xform_list_str[list_offset] = ';';
                        list_offset += 1;
                    }
                    const next = std.fmt.bufPrint(xform_list_str[list_offset..], "T{d}", .{i}) catch break;
                    list_offset += next.len;
                }
                xform_list_str[list_offset] = 0;
                const list_sentinel: [:0]const u8 = xform_list_str[0..list_offset :0];
                const dropdown_rect = rl.Rectangle.init(contentX, cy, 150, 20);
                
                // Add/Delete Buttons
                // [Dropdown] [ + ] [ - ]
                if (rg.button(rl.Rectangle.init(contentX + 160, cy, 30, 20), "+")) {
                    // Add Transform
                    const new_len = f.xforms.len + 1;
                    if (allocator.realloc(f.xforms, new_len)) |new_ptr| {
                         f.xforms = new_ptr;
                         // Initialize with identity
                         f.xforms[new_len - 1] = flame.Xform{
                             .a = 1.0, .d = 1.0, .linear = 1.0,
                         };
                         selected_xform = @as(i32, @intCast(new_len - 1));
                         history.push(f) catch {};
                         render_state.reset_histogram();
                    } else |_| {
                         // alloc failed
                    }
                }
                
                if (rg.button(rl.Rectangle.init(contentX + 195, cy, 30, 20), "-")) {
                    // Delete Transform (if > 1)
                    if (f.xforms.len > 1) {
                         const current_idx = @as(usize, @intCast(selected_xform));
                         
                         // Create new slice
                         if (allocator.alloc(flame.Xform, f.xforms.len - 1)) |new_arr| {
                             // Copy before
                             @memcpy(new_arr[0..current_idx], f.xforms[0..current_idx]);
                             // Copy after
                             @memcpy(new_arr[current_idx..], f.xforms[current_idx+1..]);
                             
                             // Free old
                             allocator.free(f.xforms);
                             f.xforms = new_arr;
                             
                             // Update selection
                             if (current_idx >= f.xforms.len) {
                                 selected_xform = @as(i32, @intCast(f.xforms.len - 1));
                             }
                             
                             history.push(f) catch {};
                             render_state.reset_histogram();
                         } else |_| {
                             // alloc failed
                         }
                    }
                }
                
                cy += 35; // Reserve space for it
                
                // If dropdown is open, DISABLE underlying controls
                if (xform_dropdown_edit_mode) rg.lock();

                if (selected_xform >= 0 and selected_xform < f.xforms.len) {
                    const idx = @as(usize, @intCast(selected_xform));
                    var xf = &f.xforms[idx];
                    var control_id: i32 = 0;

                    _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Affine");
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "X", &xf.e, -100.0, 100.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;
                    
                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Y", &xf.f, -100.0, 100.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;
                    
                    cy += 25;
                    
                    // Movement Control (Step + Arrows) moved up
                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Step", &move_step, 0.001, 1.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 30;

                    const arrow_w = 60.0;
                    const arrow_h = 25.0;
                    const arrow_cx = contentX + 60.0; // Center column

                    // Up
                    if (rg.button(rl.Rectangle.init(arrow_cx + arrow_w, cy, arrow_w, arrow_h), "Up")) {
                        xf.f += move_step; 
                        render_state.reset_histogram(); history.push(f) catch {};
                    }
                    cy += 30;
                    
                    // Left, Down, Right
                    if (rg.button(rl.Rectangle.init(arrow_cx, cy, arrow_w, arrow_h), "Left")) {
                        xf.e -= move_step;
                        render_state.reset_histogram(); history.push(f) catch {};
                    }
                    if (rg.button(rl.Rectangle.init(arrow_cx + arrow_w, cy, arrow_w, arrow_h), "Down")) {
                        xf.f -= move_step;
                        render_state.reset_histogram(); history.push(f) catch {};
                    }
                    if (rg.button(rl.Rectangle.init(arrow_cx + arrow_w * 2, cy, arrow_w, arrow_h), "Right")) {
                        xf.e += move_step;
                        render_state.reset_histogram(); history.push(f) catch {};
                    }
                    cy += 35;

                    // Scale control moved down below movement
                    const current_scale_calc = @sqrt(xf.a * xf.a + xf.b * xf.b + xf.c * xf.c + xf.d * xf.d) / 1.414;
                    var current_scale = current_scale_calc;
                    const old_scale_val = current_scale;
                    
                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Scale", &current_scale, 0.1, 50.0, &active_edit_id, control_id, &edit_buffer);
                    
                    if (@abs(current_scale - old_scale_val) > 0.001 and old_scale_val > 0.001) {
                        const scale_ratio = current_scale / old_scale_val;
                        xf.a *= scale_ratio;
                        xf.b *= scale_ratio;
                        xf.c *= scale_ratio;
                        xf.d *= scale_ratio;
                        history.push(f) catch {};
                        render_state.reset_histogram();
                    }
                    cy += 30;

                    // Rotation Control
                    _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Rotation");
                    cy += 25;
                    
                    // Calculate current angle from A/B components
                    // Angle is atan2(b, a) assuming uniform scale/no shear, but good approximation for UI
                    const current_angle_rad = std.math.atan2(xf.b, xf.a);
                    var current_angle_deg = current_angle_rad * 180.0 / std.math.pi;
                    const old_angle_deg = current_angle_deg;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Angle", &current_angle_deg, -180.0, 180.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 30;

                    if (@abs(current_angle_deg - old_angle_deg) > 0.01) {
                         // Apply rotation delta
                         xf.rotate(current_angle_deg - old_angle_deg);
                         history.push(f) catch {};
                         render_state.reset_histogram();
                    }

                    // Preset Rotation Buttons
                    // const btn_w = 40.0; // Unused
                    // Layout: 
                    // [ -180 ] [ -90  ] [ -45  ] [ +45  ] [ +90  ] [ +180 ] -> too wide?
                    // Row 1: -45 +45  -90 +90
                    // Row 2: -180 +180 -5 +5
                    
                    if (rg.button(rl.Rectangle.init(contentX, cy, 50, 20), "-45")) {
                         xf.rotate(-45.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                    if (rg.button(rl.Rectangle.init(contentX + 55, cy, 50, 20), "+45")) {
                         xf.rotate(45.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                    if (rg.button(rl.Rectangle.init(contentX + 110, cy, 50, 20), "-90")) {
                         xf.rotate(-90.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                    if (rg.button(rl.Rectangle.init(contentX + 165, cy, 50, 20), "+90")) {
                         xf.rotate(90.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                    cy += 25;

                    if (rg.button(rl.Rectangle.init(contentX, cy, 50, 20), "-180")) {
                         xf.rotate(-180.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                    if (rg.button(rl.Rectangle.init(contentX + 55, cy, 50, 20), "+180")) {
                         xf.rotate(180.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                     if (rg.button(rl.Rectangle.init(contentX + 110, cy, 50, 20), "-5")) {
                        xf.rotate(-5.0); render_state.reset_histogram(); history.push(f) catch {};
                   }
                   if (rg.button(rl.Rectangle.init(contentX + 165, cy, 50, 20), "+5")) {
                         xf.rotate(5.0); render_state.reset_histogram(); history.push(f) catch {};
                    }
                    cy += 30;


                    // Variations (Existing)
                    _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Variations");
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Lin", &xf.linear, -5.0, 5.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Sin", &xf.sinusoidal, -5.0, 5.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Sph", &xf.spherical, -5.0, 5.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Swrl", &xf.swirl, -5.0, 5.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Horse", &xf.horseshoe, -5.0, 5.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;
                }

                // NOW draw the dropdown on top
                rg.unlock();
                if (rg.dropdownBox(dropdown_rect, list_sentinel, &selected_xform, xform_dropdown_edit_mode) > 0) {
                    xform_dropdown_edit_mode = !xform_dropdown_edit_mode;
                }
            },
            .Color => {
                _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Color Palette");
                cy += 30;

                // Reserve space for gradient and markers (drawn later)
                const gradWidth: f32 = 256.0;
                // const marker_y_start = cy + 40; // Unused

                const controls_y_start = cy + 70; // 40 (grad) + 10 (padding) + 20 (markers)
                
                // We'll draw gradient and markers at the END of this block
                // so they reflect the latest baked state from the controls below.
                
                const grad_draw_y = cy;
                const marker_draw_y = cy + 50;
                
                cy = controls_y_start;

                // (Logic for node markers moved to end)
                cy += 20;
                


                // Node controls
                if (f.palette.num_nodes > 0) {
                    const idx = @as(usize, @intCast(@max(0, @min(f.palette.num_nodes - 1, @as(u32, @intCast(selected_color_node))))));
                    var node = &f.palette.nodes[idx];
                    
                    // Smart Sync (History Based):
                    // Only update picker if selection changed OR history changed (Undo/Redo/External)
                    const selection_changed = (selected_color_node != last_color_node_idx);
                    const history_changed = (history.current_idx != last_history_idx);

                    if (selection_changed or history_changed) {
                        picker_color_rl = flameToRlColor(node.color);
                        last_color_node_idx = selected_color_node;
                        last_history_idx = history.current_idx;
                    }

                    _ = rg.label(rl.Rectangle.init(contentX, cy, 50, 20), "Pos");
                    if (rg.slider(rl.Rectangle.init(contentX + 40, cy, 210, 20), "", "", &node.pos, 0.0, 1.0) != 0) {
                        f.palette.bake(&selected_color_node);
                        render_state.upload_palette(f.palette.colors[0..]);
                    }
                    cy += 30;

                    const prev_picker_color = picker_color_rl;
                    _ = rg.colorPicker(rl.Rectangle.init(contentX, cy, 200, 200), "", &picker_color_rl);
                    
                    const picker_changed = (picker_color_rl.r != prev_picker_color.r or 
                                          picker_color_rl.g != prev_picker_color.g or 
                                          picker_color_rl.b != prev_picker_color.b);

                    if (picker_changed) {
                        node.color = rlToFlameColor(picker_color_rl);
                        node.color.a = 1.0;
                        
                        f.palette.bake(&selected_color_node);
                        render_state.upload_palette(f.palette.colors[0..]);
                    }
                    cy += 210;
                }

                // Browse Gradients button


                // --- POST-UPDATE DRAWING ---
                // Now draw the gradient and markers using the potentially updated palette
                
                // 1. Gradient Strip
                const gradRect = rl.Rectangle.init(contentX, grad_draw_y, gradWidth, 40);
                for (0..256) |i| {
                    const c = flameToRlColor(f.palette.colors[i]);
                    rl.drawRectangle(@intFromFloat(contentX + @as(f32, @floatFromInt(i))), @intFromFloat(grad_draw_y), 1, 40, c);
                }
                rl.drawRectangleLinesEx(gradRect, 1, rl.Color.gray);

                // Click on gradient to select closest node
                if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                    const m = rl.getMousePosition();
                    if (rl.checkCollisionPointRec(m, gradRect)) {
                        const clickPos = (m.x - gradRect.x) / gradRect.width;
                        var min_dist: f32 = 2.0;
                        var closest_idx: i32 = 0;
                        for (0..f.palette.num_nodes) |i| {
                            const dist = @abs(f.palette.nodes[i].pos - clickPos);
                            if (dist < min_dist) {
                                min_dist = dist;
                                closest_idx = @intCast(i);
                            }
                        }
                        selected_color_node = closest_idx;
                    }
                }

                // 2. Node Markers
                for (0..f.palette.num_nodes) |i| {
                    const node = f.palette.nodes[i];
                    const nx = contentX + node.pos * (gradWidth - 1.0);
                    const is_sel = (@as(i32, @intCast(i)) == selected_color_node);
                    
                    // Use actual node color for the marker fill
                    const node_c = flameToRlColor(node.color);

                    const border_color = if (is_sel) rl.Color.white else rl.Color.dark_gray;
                    
                    const v1 = rl.Vector2.init(nx, marker_draw_y);
                    const v2 = rl.Vector2.init(nx - 6, marker_draw_y + 12);
                    const v3 = rl.Vector2.init(nx + 6, marker_draw_y + 12);

                    rl.drawTriangle(v1, v2, v3, node_c);
                    rl.drawTriangleLines(v1, v2, v3, border_color);
                    
                    // Click to select logic (can remain here)
                    if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                        const m = rl.getMousePosition();
                        if (m.x >= nx - 8 and m.x <= nx + 8 and m.y >= marker_draw_y and m.y <= marker_draw_y + 15) {
                            selected_color_node = @intCast(i);
                        }
                    }
                }

                // Add/Delete Node
                if (f.palette.num_nodes < colors.MAX_NODES) {
                    if (rg.button(rl.Rectangle.init(contentX, cy, 100, 30), "Add Node")) {
                        const new_idx = f.palette.num_nodes;
                        f.palette.nodes[new_idx] = colors.ColorNode{ 
                            .pos = 0.5, 
                            .color = colors.Color{ .r = 1, .g = 1, .b = 1 } 
                        };
                        f.palette.num_nodes += 1;
                        f.palette.bake(&selected_color_node);
                        selected_color_node = @intCast(new_idx);
                        render_state.upload_palette(f.palette.colors[0..]);
                        render_state.reset_histogram();
                        history.push(f) catch {};
                    }
                }
                if (f.palette.num_nodes > 1) {
                    if (rg.button(rl.Rectangle.init(contentX + 110, cy, 110, 30), "Delete Node")) {
                        const del_idx = @as(usize, @intCast(selected_color_node));
                        for (del_idx..f.palette.num_nodes - 1) |i| {
                            f.palette.nodes[i] = f.palette.nodes[i+1];
                        }
                        f.palette.num_nodes -= 1;
                        selected_color_node = @max(0, selected_color_node - 1);
                        f.palette.bake(&selected_color_node);
                        render_state.upload_palette(f.palette.colors[0..]);
                        render_state.reset_histogram();
                        history.push(f) catch {};
                    }
                }
                cy += 40;

                // Browse Gradients button
                if (rg.button(rl.Rectangle.init(contentX, cy, 200, 25), "Browse Gradients...")) {
                    show_gradient_browser = true;
                }
                cy += 35;
            },
        }


        // --- MENU BAR DRAWING ---
        {
            // Background
            rl.drawRectangle(0, 0, screenWidth, @intFromFloat(MENU_HEIGHT), rl.Color.light_gray);
            rl.drawLine(0, @intFromFloat(MENU_HEIGHT), screenWidth, @intFromFloat(MENU_HEIGHT), rl.Color.gray);
            
            // "File" Button
            if (rg.button(rl.Rectangle.init(0, 0, 60, MENU_HEIGHT), "File")) {
                file_menu_open = !file_menu_open;
            }
            
            // "Edit" Button
            if (rg.button(rl.Rectangle.init(60, 0, 60, MENU_HEIGHT), "Edit")) {
                edit_menu_open = !edit_menu_open;
                file_menu_open = false; // Close other menus
            }
            
            // Draw Menu Dropdown if open
            if (file_menu_open) {
                const item_height = 24.0;
                const menu_width = 120.0;
                const base_y = MENU_HEIGHT;
                
                // Background for menu
                rl.drawRectangle(0, @intFromFloat(base_y), @intFromFloat(menu_width), @intFromFloat(item_height * 3.0), rl.Color.light_gray);
                rl.drawRectangleLines(0, @intFromFloat(base_y), @intFromFloat(menu_width), @intFromFloat(item_height * 3.0), rl.Color.gray);
                
                // Menu Items
                if (rg.button(rl.Rectangle.init(0, base_y, menu_width, item_height), "Open .flamey")) {
                     file_menu_open = false; // Close menu
                     if (io.IO.loadFlam3Yaml(allocator, "fractal.flamey")) |loaded_f| {
                          f = loaded_f;
                          zoom = 50.0;
                          gamma = f.gamma;
                          brightness = f.brightness;
                          vibrancy = f.vibrancy;
                          selected_xform = 0;
                          render_state.reset_histogram();
                          // Force picker sync
                          last_color_node_idx = -1;
                     } else |err| {
                          std.debug.print("Failed to load: {}\n", .{err});
                     }
                }
                
                if (rg.button(rl.Rectangle.init(0, base_y + item_height, menu_width, item_height), "Save .flamey")) {
                     file_menu_open = false;
                     io.IO.saveFlam3Yaml("fractal.flamey", f) catch |err| {
                         std.debug.print("Failed to save: {}\n", .{err});
                     };
                }
                
                if (rg.button(rl.Rectangle.init(0, base_y + item_height * 2, menu_width, item_height), "Import .flame")) {
                     file_menu_open = false;
                     if (io.IO.loadLegacyFlameXml(allocator, "fractal.flame")) |loaded_f| {
                          f = loaded_f;
                          zoom = 50.0;
                          gamma = f.gamma;
                          brightness = f.brightness;
                          vibrancy = f.vibrancy;
                          selected_xform = 0;
                          render_state.reset_histogram();
                          // Force picker sync
                          last_color_node_idx = -1;
                     } else |err| {
                          std.debug.print("Failed to load .flame: {}\n", .{err});
                     }
                }
                
                // Click outside to close
                if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                    const m = rl.getMousePosition();
                    // If click is outside the menu rect AND outside the File button (which handles toggle)
                    if (m.y > MENU_HEIGHT) { // Below menu bar
                         if (m.x > menu_width or m.y > base_y + item_height * 3.0) {
                             file_menu_open = false;
                         }
                    } else {
                        // In menu bar. If NOT file button (0..60), close?
                        // "Edit" button logic might interfere. 
                        // Let's just say: If you click outside the dropdown, close it.
                        if (m.x > menu_width) file_menu_open = false;
                    }
                }
            }
            
            // Edit Menu Dropdown
            if (edit_menu_open) {
                const i_height = 24.0;
                const m_width = 170.0;
                const b_y = MENU_HEIGHT;
                
                // Background
                rl.drawRectangle(60, @intFromFloat(b_y), @intFromFloat(m_width), @intFromFloat(i_height * 4.0), rl.Color.light_gray);
                rl.drawRectangleLines(60, @intFromFloat(b_y), @intFromFloat(m_width), @intFromFloat(i_height * 4.0), rl.Color.gray);
                
                // Undo
                const can_undo = history.canUndo();
                rg.setState(if (can_undo) 0 else 1);
                if (rg.button(rl.Rectangle.init(60, b_y, m_width, i_height), "Undo (Ctrl+Z)")) {
                    if (can_undo) {
                        if (history.undo()) |prev_flame| {
                            f = prev_flame;
                            selected_xform = @min(selected_xform, @as(i32, @intCast(f.xforms.len - 1)));
                            render_state.reset_histogram();
                        }
                        edit_menu_open = false;
                    }
                }
                rg.setState(0);
                
                // Redo
                const can_redo = history.canRedo();
                rg.setState(if (can_redo) 0 else 1);
                if (rg.button(rl.Rectangle.init(60, b_y + i_height, m_width, i_height), "Redo (Ctrl+Shift+Z)")) {
                    if (can_redo) {
                        if (history.redo()) |next_flame| {
                            f = next_flame;
                            selected_xform = @min(selected_xform, @as(i32, @intCast(f.xforms.len - 1)));
                            render_state.reset_histogram();
                        }
                        edit_menu_open = false;
                    }
                }
                rg.setState(0);
                
                // Add Transform
                if (rg.button(rl.Rectangle.init(60, b_y + i_height * 2, m_width, i_height), "Add Transform")) {
                    const new_xforms = allocator.alloc(flame.Xform, f.xforms.len + 1) catch blk: {
                        std.debug.print("Failed to allocate\n", .{});
                        break :blk f.xforms;
                    };
                    if (new_xforms.ptr != f.xforms.ptr) {
                        @memcpy(new_xforms[0..f.xforms.len], f.xforms);
                        new_xforms[f.xforms.len] = flame.Xform{ .linear = 1.0, .color = 0.5 };
                        f.xforms = new_xforms;
                        selected_xform = @intCast(f.xforms.len - 1);
                        history.push(f) catch {};
                        render_state.reset_histogram();
                    }
                    edit_menu_open = false;
                }
                
                // Delete Transform
                const can_delete = f.xforms.len > 1;
                rg.setState(if (can_delete) 0 else 1);
                if (rg.button(rl.Rectangle.init(60, b_y + i_height * 3, m_width, i_height), "Delete Transform")) {
                    if (can_delete and selected_xform >= 0 and selected_xform < f.xforms.len) {
                        const new_xforms = allocator.alloc(flame.Xform, f.xforms.len - 1) catch blk: {
                            std.debug.print("Failed to allocate\n", .{});
                            break :blk f.xforms;
                        };
                        if (new_xforms.ptr != f.xforms.ptr) {
                            const idx = @as(usize, @intCast(selected_xform));
                            if (idx > 0) @memcpy(new_xforms[0..idx], f.xforms[0..idx]);
                            if (idx < f.xforms.len - 1) @memcpy(new_xforms[idx..], f.xforms[idx+1..]);
                            f.xforms = new_xforms;
                            selected_xform = @min(selected_xform, @as(i32, @intCast(f.xforms.len - 1)));
                            history.push(f) catch {};
                            render_state.reset_histogram();
                        }
                    }
                    edit_menu_open = false;
                }
                rg.setState(0);
                
                // Click outside to close
                if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                    const m = rl.getMousePosition();
                    if (m.y > MENU_HEIGHT) {
                         if (m.x < 60 or m.x > 60 + m_width or m.y > b_y + i_height * 4.0) {
                             edit_menu_open = false;
                         }
                    } else {
                        if (m.x < 60 or m.x > 60 + m_width) edit_menu_open = false;
                    }
                }
            }
        }
        
        // --- GRADIENT BROWSER MODAL WINDOW ---
        if (show_gradient_browser) {
            // Semi-transparent overlay
            rl.drawRectangle(0, 0, screenWidth, screenHeight, rl.Color{.r = 0, .g = 0, .b = 0, .a = 180});
            
            // Modal window
            const modal_width: f32 = 500.0;
            const modal_height: f32 = 600.0;
            const modal_x = (@as(f32, @floatFromInt(screenWidth)) - modal_width) / 2.0;
            const modal_y = (@as(f32, @floatFromInt(screenHeight)) - modal_height) / 2.0;
            
            rl.drawRectangle(@intFromFloat(modal_x), @intFromFloat(modal_y), @intFromFloat(modal_width), @intFromFloat(modal_height), rl.Color.light_gray);
            _ = rg.panel(rl.Rectangle.init(modal_x, modal_y, modal_width, modal_height), "Gradient Library");
            
            var modal_cy = modal_y + 30;
            const btn_height: f32 = 25;
            
            // Top toolbar: File Path Input
            _ = rg.label(rl.Rectangle.init(modal_x + 10, modal_cy, 50, btn_height), "File:");
            if (rg.textBox(rl.Rectangle.init(modal_x + 50, modal_cy, modal_width - 150, btn_height), gradient_file_path_buf[0..], 256, true)) {
                // Path edited
            }
            
            if (rg.button(rl.Rectangle.init(modal_x + modal_width - 90, modal_cy, 80, btn_height), "Open")) {
                const path = std.mem.span(@as([*:0]u8, @ptrCast(&gradient_file_path_buf)));
                gradient_library.clear();
                gradient_library.loadFromFile(path) catch |err| {
                    std.debug.print("Failed to load {s}: {}\n", .{path, err});
                };
            }
            
            modal_cy += btn_height + 10;
            
            // Second row: Management buttons
            var btn_x = modal_x + 10;
            const sub_btn_width = (modal_width - 30) / 3;
            
            if (rg.button(rl.Rectangle.init(btn_x, modal_cy, sub_btn_width, btn_height), "Save As...")) {
                const path = std.mem.span(@as([*:0]u8, @ptrCast(&gradient_file_path_buf)));
                gradient_library.saveToFile(path) catch |e| {
                    std.debug.print("Save failed: {}\n", .{e});
                };
            }
            btn_x += sub_btn_width + 5;
            
            if (rg.button(rl.Rectangle.init(btn_x, modal_cy, sub_btn_width, btn_height), "Add Current")) {
                const name_buf = std.fmt.allocPrint(allocator, "New Gradient {d}", .{gradient_library.gradients.items.len + 1}) catch null;
                if (name_buf) |name| {
                    const node_slice = allocator.alloc(colors.ColorNode, f.palette.num_nodes) catch null;
                    if (node_slice) |nodes| {
                        var new_entry = gradient_browser.GradientEntry{
                            .name = name,
                            .colors = undefined,
                            .nodes = nodes,
                        };
                        @memcpy(&new_entry.colors, &f.palette.colors);
                        for (0..f.palette.num_nodes) |ni| {
                            nodes[ni] = f.palette.nodes[ni];
                        }
                        gradient_library.add(new_entry) catch |err| {
                            std.debug.print("Failed to add gradient: {}\n", .{err});
                            allocator.free(name);
                            allocator.free(nodes);
                        };
                    } else {
                        allocator.free(name);
                    }
                }
            }
            btn_x += sub_btn_width + 5;
            
            const can_delete = (gradient_browser_selected != null);
            rg.setState(if (can_delete) 0 else 1);
            if (rg.button(rl.Rectangle.init(btn_x, modal_cy, sub_btn_width, btn_height), "Remove")) {
                if (gradient_browser_selected) |sel_idx| {
                    gradient_library.remove(sel_idx);
                    gradient_browser_selected = null;
                }
            }
            rg.setState(0);
            
            modal_cy += btn_height + 15;
            
            // Gradient gallery (scrollable area)
            const gallery_y = modal_cy;
            const gallery_height = modal_height - (gallery_y - modal_y) - 60; // Leave space for bottom buttons
            const gallery_rect = rl.Rectangle.init(modal_x + 10, gallery_y, modal_width - 20, gallery_height);
            
            // Draw gallery background
            rl.drawRectangleRec(gallery_rect, rl.Color.white);
            rl.drawRectangleLinesEx(gallery_rect, 1, rl.Color.gray);
            
            // Handle scrolling
            const wheel = rl.getMouseWheelMove();
            if (wheel != 0) {
                gradient_browser_scroll -= wheel * 30.0;
            }

            // Draw gradients
            const grad_bar_height: f32 = 25; // Slightly shorter to fit more
            const grad_spacing: f32 = 10;
            const item_height = grad_bar_height + 18 + grad_spacing;
            
            // Clamp scroll
            const total_content_height = @as(f32, @floatFromInt(gradient_library.gradients.items.len)) * item_height;
            gradient_browser_scroll = @max(0.0, @min(gradient_browser_scroll, @max(0.0, total_content_height - gallery_height + 20)));

            rl.beginScissorMode(@intFromFloat(gallery_rect.x), @intFromFloat(gallery_rect.y), @intFromFloat(gallery_rect.width), @intFromFloat(gallery_rect.height));
            
            var grad_y = gallery_y + 5 - gradient_browser_scroll;
            
            for (gradient_library.gradients.items, 0..) |entry, i| {
                const is_selected = if (gradient_browser_selected) |sel| sel == i else false;
                const bar_rect = rl.Rectangle.init(gallery_rect.x + 5, grad_y, gallery_rect.width - 25, grad_bar_height);
                
                // Skip if out of view
                if (grad_y + item_height >= gallery_y and grad_y <= gallery_y + gallery_height) {
                    // Selection highlight
                    if (is_selected) {
                        rl.drawRectangleRec(
                            rl.Rectangle.init(bar_rect.x - 2, bar_rect.y - 2, bar_rect.width + 4, bar_rect.height + 4),
                            rl.Color.sky_blue
                        );
                    }
                    
                    // Draw gradient
                    for (0..256) |px| {
                        const x_pos = bar_rect.x + (@as(f32, @floatFromInt(px)) / 255.0) * bar_rect.width;
                        const c = entry.colors[px];
                        const rl_color = flameToRlColor(c);
                        rl.drawRectangle(@intFromFloat(x_pos), @intFromFloat(bar_rect.y), 2, @intFromFloat(bar_rect.height), rl_color);
                    }
                    
                    // Click to select
                    if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                        const m = rl.getMousePosition();
                        if (rl.checkCollisionPointRec(m, bar_rect)) {
                            gradient_browser_selected = i;
                        }
                    }

                    // Right-click context menu
                    if (rl.isMouseButtonPressed(rl.MouseButton.right)) {
                        const m = rl.getMousePosition();
                        if (rl.checkCollisionPointRec(m, bar_rect)) {
                            gradient_context_menu_open = true;
                            gradient_context_menu_pos = m;
                            gradient_context_menu_idx = i;
                        }
                    }
                    
                    // Draw name label
                    const label_cstr = std.fmt.bufPrintZ(&gradient_file_path_buf, "{s}", .{entry.name}) catch "???";
                    rl.drawText(label_cstr, @intFromFloat(bar_rect.x), @intFromFloat(grad_y + grad_bar_height + 2), 10, rl.Color.black);
                }
                
                grad_y += item_height;
            }
            rl.endScissorMode();


            
            // Bottom buttons
            const bottom_y = modal_y + modal_height - 45;
            const bottom_btn_width: f32 = 120;
            
            if (rg.button(rl.Rectangle.init(modal_x + modal_width - bottom_btn_width - 140, bottom_y, bottom_btn_width, 30), "Cancel")) {
                show_gradient_browser = false;
                gradient_browser_selected = null;
                gradient_context_menu_open = false;
            }
            
            rg.setState(if (gradient_browser_selected != null) 0 else 1);
            if (rg.button(rl.Rectangle.init(modal_x + modal_width - bottom_btn_width - 10, bottom_y, bottom_btn_width, 30), "Select Gradient")) {
                if (gradient_browser_selected) |sel_idx| {
                    // Apply gradient to current palette
                    const selected_grad = gradient_library.gradients.items[sel_idx];
                    
                    // Copy 256 colors
                    @memcpy(&f.palette.colors, &selected_grad.colors);
                    
                    // Copy nodes (clamped to MAX_NODES)
                    const num_nodes = @min(selected_grad.nodes.len, colors.MAX_NODES);
                    f.palette.num_nodes = @intCast(num_nodes);
                    for (0..num_nodes) |ni| {
                        f.palette.nodes[ni] = selected_grad.nodes[ni];
                    }
                    selected_color_node = 0; // Reset selection to first node
                    f.palette.bake(null);

                    render_state.upload_palette(f.palette.colors[0..]);
                    render_state.reset_histogram();
                    history.push(f) catch {};
                    show_gradient_browser = false;
                    gradient_browser_selected = null;
                    gradient_context_menu_open = false;
                }
            }
            rg.setState(0);

            // --- CONTEXT MENU ---
            if (gradient_context_menu_open) {
                const menu_width: f32 = 180;
                const menu_item_height: f32 = 25;
                const menu_height: f32 = menu_item_height * 4;
                
                var mx = gradient_context_menu_pos.x;
                var my = gradient_context_menu_pos.y;
                
                if (mx + menu_width > @as(f32, @floatFromInt(screenWidth))) mx -= menu_width;
                if (my + menu_height > @as(f32, @floatFromInt(screenHeight))) my -= menu_height;
                
                const menu_rect = rl.Rectangle.init(mx, my, menu_width, menu_height);
                // Background shadow
                rl.drawRectangleRec(rl.Rectangle.init(mx + 2, my + 2, menu_width, menu_height), rl.Color{ .r = 0, .g = 0, .b = 0, .a = 50 });
                rl.drawRectangleRec(menu_rect, rl.Color.white);
                rl.drawRectangleLinesEx(menu_rect, 1, rl.Color.gray);
                
                var item_y = my;
                const target_idx = gradient_context_menu_idx;
                const entry = gradient_library.gradients.items[target_idx];

                // 1. Use Gradient
                if (rg.button(rl.Rectangle.init(mx, item_y, menu_width, menu_item_height), "Use Gradient")) {
                    @memcpy(&f.palette.colors, &entry.colors);
                    const num_nodes = @min(entry.nodes.len, colors.MAX_NODES);
                    f.palette.num_nodes = @intCast(num_nodes);
                    for (0..num_nodes) |ni| {
                        f.palette.nodes[ni] = entry.nodes[ni];
                    }
                    selected_color_node = 0;
                    f.palette.bake(null);
                    render_state.upload_palette(f.palette.colors[0..]);
                    render_state.reset_histogram();
                    history.push(f) catch {};
                    show_gradient_browser = false;
                    gradient_context_menu_open = false;
                }
                item_y += menu_item_height;

                // 2. Copy Gradient
                if (rg.button(rl.Rectangle.init(mx, item_y, menu_width, menu_item_height), "Copy Gradient")) {
                    if (gradient_clipboard) |*cp| cp.deinit(allocator);
                    gradient_clipboard = entry.clone(allocator) catch null;
                    gradient_context_menu_open = false;
                }
                item_y += menu_item_height;

                // 3. Paste Gradient
                rg.setState(if (gradient_clipboard != null) 0 else 1); // 1 = GUI_STATE_DISABLED
                if (rg.button(rl.Rectangle.init(mx, item_y, menu_width, menu_item_height), "Paste Gradient")) {
                    if (gradient_clipboard) |cp| {
                        var target = &gradient_library.gradients.items[target_idx];
                        const old_name = target.name;
                        const old_nodes = target.nodes;
                        
                        if (allocator.dupe(u8, cp.name)) |new_name| {
                            if (allocator.dupe(colors.ColorNode, cp.nodes)) |new_nodes| {
                                target.name = new_name;
                                target.nodes = new_nodes;
                                @memcpy(&target.colors, &cp.colors);
                                allocator.free(old_name);
                                allocator.free(old_nodes);
                            } else |_| {
                                allocator.free(new_name);
                            }
                        } else |_| {}
                    }
                    gradient_context_menu_open = false;
                }
                rg.setState(0);
                item_y += menu_item_height;

                // 4. Delete Gradient
                if (rg.button(rl.Rectangle.init(mx, item_y, menu_width, menu_item_height), "Delete Gradient")) {
                    var del_entry = gradient_library.gradients.orderedRemove(target_idx);
                    del_entry.deinit(allocator);
                    if (gradient_browser_selected) |sel| {
                        if (sel == target_idx) {
                            gradient_browser_selected = null;
                        } else if (sel > target_idx) {
                            gradient_browser_selected = sel - 1;
                        }
                    }
                    gradient_context_menu_open = false;
                }

                // Close if clicked elsewhere
                if (rl.isMouseButtonPressed(rl.MouseButton.left) and !rl.checkCollisionPointRec(rl.getMousePosition(), menu_rect)) {
                    gradient_context_menu_open = false;
                }
            }
        }

        rl.drawText("FPS:", 10, screenHeight - 20, 20, rl.Color.white);
        rl.drawFPS(60, screenHeight - 20);
    }
}
