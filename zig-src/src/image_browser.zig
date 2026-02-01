const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

pub const ImageBrowser = struct {
    current_path_buf: [1024:0]u8,
    files: rl.FilePathList,
    selected_idx: i32 = -1,
    scroll: rl.Vector2 = .{ .x = 0, .y = 0 },
    allocator: std.mem.Allocator,
    is_active: bool = false,

    pub fn init(allocator: std.mem.Allocator) !ImageBrowser {
        var self = ImageBrowser{
            .current_path_buf = undefined,
            .files = undefined,
            .allocator = allocator,
        };
        @memset(self.current_path_buf[0..], 0);
        
        const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd);
        
        const len = @min(cwd.len, 1023);
        @memcpy(self.current_path_buf[0..len], cwd[0..len]);
        self.current_path_buf[len] = 0;
        
        self.files = rl.loadDirectoryFiles(self.current_path_buf[0..len :0]);
        return self;
    }

    pub fn deinit(self: *ImageBrowser) void {
        rl.unloadDirectoryFiles(self.files);
    }

    fn isImage(path: [:0]const u8) bool {
        const ext = std.fs.path.extension(std.mem.sliceTo(path, 0));
        const supported = [_][]const u8{ ".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tga", ".pic", ".pnm" };
        for (supported) |s| {
            if (std.ascii.eqlIgnoreCase(ext, s)) return true;
        }
        return false;
    }

    pub fn navigateTo(self: *ImageBrowser, new_path: []const u8) void {
        rl.unloadDirectoryFiles(self.files);
        @memset(self.current_path_buf[0..], 0);
        const len = @min(new_path.len, 1023);
        @memcpy(self.current_path_buf[0..len], new_path[0..len]);
        self.current_path_buf[len] = 0;
        self.files = rl.loadDirectoryFiles(self.current_path_buf[0..len :0]);
        self.selected_idx = -1;
        self.scroll = .{ .x = 0, .y = 0 };
    }

    pub fn draw(self: *ImageBrowser, bounds: rl.Rectangle) ?[:0]const u8 {
        if (!self.is_active) return null;

        // Dim background
        rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rl.fade(rl.Color.black, 0.5));

        // Window background
        rl.drawRectangleRec(bounds, rl.Color.fromInt(0x242424FF));
        rl.drawRectangleLinesEx(bounds, 1, rl.Color.gray);

        const margin: f32 = 10;
        const top_bar_h: f32 = 30;
        const bottom_bar_h: f32 = 40;
        
        // Header
        _ = rg.label(rl.Rectangle.init(bounds.x + margin, bounds.y + margin, 200, 25), "Select Image");

        // Top Bar: Current Path
        const path_rect = rl.Rectangle.init(bounds.x + margin, bounds.y + margin + 30, bounds.width - 2 * margin - 60, top_bar_h);
        _ = rg.label(path_rect, &self.current_path_buf);
        
        // Up button
        if (rg.button(rl.Rectangle.init(bounds.x + bounds.width - margin - 50, bounds.y + margin + 30, 50, top_bar_h), "Up")) {
            const path = std.mem.sliceTo(&self.current_path_buf, 0);
            if (std.fs.path.dirname(path)) |parent| {
                self.navigateTo(parent);
            } else {
                // Root? Try to list drives on Windows or just ignore
            }
        }

        // List area
        const list_rect = rl.Rectangle.init(bounds.x + margin, bounds.y + margin + 70, bounds.width - 2 * margin, bounds.height - margin - 70 - bottom_bar_h - 20);
        
        // Filter files? For now show all but only allow selecting images
        const item_h: f32 = 25;
        const content_h = @as(f32, @floatFromInt(self.files.count)) * item_h;
        
        var view = rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
        _ = rg.scrollPanel(list_rect, "Files", rl.Rectangle.init(0, 0, list_rect.width - 15, content_h), &self.scroll, &view);
        
        rl.beginScissorMode(@intCast(@as(i32, @intFromFloat(view.x))), @intCast(@as(i32, @intFromFloat(view.y))), @intCast(@as(i32, @intFromFloat(view.width))), @intCast(@as(i32, @intFromFloat(view.height))));
        
        for (0..self.files.count) |i| {
            const f_path = self.files.paths[i];
            const f_path_z = std.mem.span(f_path);
            const is_dir = rl.directoryExists(f_path_z);
            const is_img = isImage(f_path_z);
            const name = std.fs.path.basename(std.mem.sliceTo(f_path, 0));
            
            const item_y = view.y + self.scroll.y + @as(f32, @floatFromInt(i)) * item_h;
            const item_rect = rl.Rectangle.init(view.x, item_y, view.width, item_h);
            
            var label_buf: [512]u8 = undefined;
            const label_raw: [:0]const u8 = if (is_dir) 
                std.fmt.bufPrintZ(&label_buf, "DIR: {s}", .{name}) catch "DIR" 
            else 
                std.fmt.bufPrintZ(&label_buf, "{s}", .{name}) catch "FILE";
            
            // Only highlight if it's an image or dir
            if (!is_dir and !is_img) {
                rg.lock();
            }
            
            const state = @as(i32, @intCast(if (self.selected_idx == @as(i32, @intCast(i))) @intFromEnum(rg.State.pressed) else @intFromEnum(rg.State.normal)));
            rg.setState(state);
            
            if (rg.button(item_rect, label_raw)) {
                if (is_dir) {
                    self.navigateTo(std.mem.sliceTo(f_path, 0));
                    break;
                } else if (is_img) {
                    self.selected_idx = @intCast(i);
                }
            }
            
            rg.unlock();
        }
        
        rl.endScissorMode();

        // Bottom Bar: Select / Cancel
        const btn_y = bounds.y + bounds.height - margin - 30;
        if (rg.button(rl.Rectangle.init(bounds.x + bounds.width - margin - 100, btn_y, 100, 30), "Select")) {
            if (self.selected_idx >= 0) {
                const result = self.files.paths[@intCast(self.selected_idx)];
                self.is_active = false;
                return std.mem.span(result);
            }
        }
        
        if (rg.button(rl.Rectangle.init(bounds.x + margin, btn_y, 100, 30), "Cancel")) {
            self.is_active = false;
        }
        
        return null;
    }
};
