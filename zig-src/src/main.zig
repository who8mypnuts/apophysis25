const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const flame = @import("flame.zig");
const colors = @import("colors.zig");
const renderer = @import("renderer.zig");
const io = @import("io.zig");

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
    var temp_buf: [32]u8 = undefined;
    var buf_ptr: [:0]u8 = undefined;
    
    if (is_editing) {
        // Use shared buffer (already seeded)
        // We need to ensure it's null-terminated for C interop
        // shared_buffer slice should be effectively [:0]u8 compliant if we manage it right.
        shared_buffer[shared_buffer.len-1] = 0; // Safety
        buf_ptr = shared_buffer[0 .. shared_buffer.len-1 :0];
    } else {
        // Display mode
        buf_ptr = std.fmt.bufPrintZ(&temp_buf, "{d:.3}", .{value.*}) catch blk: {
            temp_buf[0] = 0;
            break :blk temp_buf[0..0 :0];
        };
    }

    if (rg.valueBoxFloat(boxBounds, "", buf_ptr, value, is_editing) != 0) {
        if (is_editing) {
            // Stopped editing (Enter pressed or lost focus)
            active_id.* = -1;
        } else {
            // Started editing
            active_id.* = this_id;
            // Seed the shared buffer
            _ = std.fmt.bufPrintZ(shared_buffer, "{d:.3}", .{value.*}) catch {};
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
    var active_tab: enum { Fractal, Transform } = .Fractal;
    var xform_dropdown_edit_mode: bool = false;
    
    // Triangle Editor State
    var drag_mode: enum { None, DragO, DragX, DragY, DragScale } = .None;
    var drag_start_mouse: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 };
    var drag_start_val: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 }; // Stores original O, X, or Y world pos
    
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

        // --- Triangle Editor Overlay ---
        const rWidthF = @as(f32, @floatFromInt(renderWidth));
        const rHeightF = @as(f32, @floatFromInt(renderHeight));
        var mouse_pos = rl.getMousePosition();
        
        // Adjust mouse for menu offset
        mouse_pos.y -= MENU_HEIGHT;
        
        
        const raw_mouse = rl.getMousePosition();
        const mouse_on_menu = (raw_mouse.y < MENU_HEIGHT);
        
        // Only block if mouse is in menu bar OR in an open menu dropdown area
        var input_blocked = mouse_on_menu;
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
        
        
        
        // Input Handling - Mouse Press (only when not blocked)
        if (!input_blocked and selected_xform >= 0 and selected_xform < f.xforms.len) {
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
                     }
                     }
                 }
             }
        }
        
        // Mouse Release - always check if we're dragging
        if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
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
                 rl.drawText("Y", @as(i32, @intFromFloat(Y_draw.x)) + 5, @as(i32, @intFromFloat(Y_draw.y)) + 5, 10, rl.Color.white);
            }
        }

        // Draw GUI Panel
        const guiWidth = screenWidth - renderWidth;
        _ = rg.panel(rl.Rectangle.init(@floatFromInt(renderWidth), 0, @floatFromInt(guiWidth), @floatFromInt(screenHeight)), "Editor");
        
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
        }
        tabY += tabHeight + 5;
        
        // Transform tab
        const transform_active = (active_tab == .Transform);
        const transform_text = if (transform_active) "#Transform#" else "Transform";
        if (rg.button(rl.Rectangle.init(panelX + 5, tabY, tabWidth, tabHeight), transform_text)) {
            active_tab = .Transform;
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
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "X", &xf.e, -2.0, 2.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;
                    
                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Y", &xf.f, -2.0, 2.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;
                    
                    // Scale control
                    const current_scale_calc = @sqrt(xf.a * xf.a + xf.b * xf.b + xf.c * xf.c + xf.d * xf.d) / 1.414;
                    var current_scale = current_scale_calc;
                    const old_scale_val = current_scale;
                    
                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Scale", &current_scale, 0.1, 5.0, &active_edit_id, control_id, &edit_buffer);
                    
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
                    
                    // Variations
                    _ = rg.label(rl.Rectangle.init(contentX, cy, 100, 20), "Variations");
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Lin", &xf.linear, 0.0, 1.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Sin", &xf.sinusoidal, 0.0, 1.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Sph", &xf.spherical, 0.0, 1.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Swrl", &xf.swirl, 0.0, 1.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;

                    control_id += 1;
                    drawFloatControl(rl.Rectangle.init(contentX, cy, 250, 20), "Horse", &xf.horseshoe, 0.0, 1.0, &active_edit_id, control_id, &edit_buffer);
                    cy += 25;
                }

                // NOW draw the dropdown on top
                rg.unlock();
                if (rg.dropdownBox(dropdown_rect, list_sentinel, &selected_xform, xform_dropdown_edit_mode) > 0) {
                    xform_dropdown_edit_mode = !xform_dropdown_edit_mode;
                }
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

        rl.drawText("FPS:", 10, screenHeight - 20, 20, rl.Color.white);
        rl.drawFPS(60, screenHeight - 20);
    }
}
