const std = @import("std");
const colors = @import("colors.zig");

/// Sparse color entry used during parsing
const SparseColorEntry = struct {
    index: u8,
    color: u32,
};

/// Represents a single gradient with a name and 256 colors
pub const GradientEntry = struct {
    name: []u8,
    colors: [256]colors.Color,
    nodes: []colors.ColorNode,
    
    pub fn deinit(self: *GradientEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.nodes);
    }

    pub fn clone(self: GradientEntry, allocator: std.mem.Allocator) !GradientEntry {
        const new_name = try allocator.dupe(u8, self.name);
        errdefer allocator.free(new_name);
        const new_nodes = try allocator.dupe(colors.ColorNode, self.nodes);
        errdefer allocator.free(new_nodes);
        
        return GradientEntry{
            .name = new_name,
            .colors = self.colors,
            .nodes = new_nodes,
        };
    }
};

/// Manages a collection of gradients loaded from .ugr files
pub const GradientLibrary = struct {
    gradients: std.ArrayListUnmanaged(GradientEntry),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) GradientLibrary {
        return .{
            .gradients = .{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *GradientLibrary) void {
        for (self.gradients.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.gradients.deinit(self.allocator);
    }
    
    pub fn add(self: *GradientLibrary, entry: GradientEntry) !void {
        try self.gradients.append(self.allocator, entry);
    }
    
    pub fn remove(self: *GradientLibrary, index: usize) void {
        if (index < self.gradients.items.len) {
            var entry = self.gradients.orderedRemove(index);
            entry.deinit(self.allocator);
        }
    }
    
    pub fn clear(self: *GradientLibrary) void {
        for (self.gradients.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.gradients.clearRetainingCapacity();
    }
    
    /// Parse a .ugr file and load all gradients
    pub fn loadFromFile(self: *GradientLibrary, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);
        
        try self.parseUGR(content);
    }
    
    /// Parse UGR format content
    fn parseUGR(self: *GradientLibrary, content: []const u8) !void {
        var lines = std.mem.splitSequence(u8, content, "\n");
        var current_gradient: ?struct {
            name: []const u8,
            sparse_colors: std.ArrayListUnmanaged(SparseColorEntry),
        } = null;
        
        while (lines.next()) |line_raw| {
            // Trim whitespace and \r
            var line = std.mem.trim(u8, line_raw, " \t\r");
            
            // Skip empty lines
            if (line.len == 0) continue;
            
            // Check for gradient name (e.g., "001 {")
            if (std.mem.indexOf(u8, line, " {")) |brace_pos| {
                const name = std.mem.trim(u8, line[0..brace_pos], " \t");
                current_gradient = .{
                    .name = name,
                    .sparse_colors = .{},
                };
            }
            
            // Check for closing brace
            else if (std.mem.eql(u8, line, "}")) {
                if (current_gradient) |*grad| {
                    // Convert sparse colors to nodes
                    var nodes = try self.allocator.alloc(colors.ColorNode, grad.sparse_colors.items.len);
                    for (grad.sparse_colors.items, 0..) |sparse_entry, i| {
                        nodes[i] = colors.ColorNode{
                            .pos = @as(f32, @floatFromInt(sparse_entry.index)) / 255.0,
                            .color = unpackColor(sparse_entry.color),
                        };
                    }

                    // Convert sparse colors to full 256-color palette
                    var entry = GradientEntry{
                        .name = try self.allocator.dupe(u8, grad.name),
                        .colors = undefined,
                        .nodes = nodes,
                    };
                    
                    // Interpolate colors
                    try interpolateColors(&entry.colors, grad.sparse_colors.items);
                    
                    try self.add(entry);
                    
                    grad.sparse_colors.deinit(self.allocator);
                    current_gradient = null;
                }
            }
            
            // Parse color line (e.g., " index=0 color=2760960")
            else if (current_gradient) |*grad| {
                if (parseColorLine(line)) |color_entry| {
                    try grad.sparse_colors.append(self.allocator, color_entry);
                }
            }
        }
    }
    
    /// Save all gradients to a .ugr file
    pub fn saveToFile(self: *GradientLibrary, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        for (self.gradients.items) |entry| {
            // Header
            var header_buf: [512]u8 = undefined;
            const header = try std.fmt.bufPrint(&header_buf, "{s} {{\ngradient:\n title=\"{s}\" smooth=no\n", .{ entry.name, entry.name });
            try file.writeAll(header);
            
            // 256 color entries
            for (entry.colors, 0..) |color, i| {
                const packed_rgb = packColor(color);
                var line_buf: [128]u8 = undefined;
                const line = try std.fmt.bufPrint(&line_buf, " index={d} color={d}\n", .{ i, packed_rgb });
                try file.writeAll(line);
            }
            
            // Footer
            try file.writeAll("}\n\n");
        }
    }
};

/// Parse a single color line like " index=5 color=123456"
fn parseColorLine(line: []const u8) ?SparseColorEntry {
    // Look for "index="
    const index_start = std.mem.indexOf(u8, line, "index=") orelse return null;
    const index_value_start = index_start + 6;
    
    // Find end of index number (space)
    var index_value_end = index_value_start;
    while (index_value_end < line.len and line[index_value_end] != ' ') : (index_value_end += 1) {}
    
    const index_str = line[index_value_start..index_value_end];
    const index = std.fmt.parseInt(u8, index_str, 10) catch return null;
    
    // Look for "color="
    const color_start = std.mem.indexOf(u8, line, "color=") orelse return null;
    const color_value_start = color_start + 6;
    
    // Find end of color number
    var color_value_end = color_value_start;
    while (color_value_end < line.len and line[color_value_end] >= '0' and line[color_value_end] <= '9') : (color_value_end += 1) {}
    
    const color_str = line[color_value_start..color_value_end];
    const color = std.fmt.parseInt(u32, color_str, 10) catch return null;
    
    return .{ .index = index, .color = color };
}

/// Convert packed RGB integer to Color struct
fn unpackColor(packed_rgb: u32) colors.Color {
    const r = @as(u8, @intCast(packed_rgb & 0xFF));
    const g = @as(u8, @intCast((packed_rgb >> 8) & 0xFF));
    const b = @as(u8, @intCast((packed_rgb >> 16) & 0xFF));
    
    return colors.Color{
        .r = @as(f32, @floatFromInt(r)) / 255.0,
        .g = @as(f32, @floatFromInt(g)) / 255.0,
        .b = @as(f32, @floatFromInt(b)) / 255.0,
        .a = 1.0,
    };
}

/// Convert Color struct to packed RGB integer
fn packColor(c: colors.Color) u32 {
    const r = @as(u32, @intFromFloat(c.r * 255.0));
    const g = @as(u32, @intFromFloat(c.g * 255.0));
    const b = @as(u32, @intFromFloat(c.b * 255.0));
    return r | (g << 8) | (b << 16);
}

/// Interpolate sparse color entries to fill all 256 slots
fn interpolateColors(out: *[256]colors.Color, sparse: []const SparseColorEntry) !void {
    if (sparse.len == 0) {
        // Default to black if no colors
        for (out) |*c| {
            c.* = colors.Color{ .r = 0, .g = 0, .b = 0, .a = 1 };
        }
        return;
    }
    
    // Fill in the sparse entries first
    for (sparse) |entry| {
        out[entry.index] = unpackColor(entry.color);
    }
    
    // Interpolate between defined indices
    var last_index: usize = sparse[0].index;
    for (0..sparse.len - 1) |i| {
        const start_idx = sparse[i].index;
        const end_idx = sparse[i + 1].index;
        const start_color = out[start_idx];
        const end_color = out[end_idx];
        
        // Interpolate
        for (@as(usize, start_idx) + 1..end_idx) |j| {
            const t = @as(f32, @floatFromInt(j - start_idx)) / @as(f32, @floatFromInt(end_idx - start_idx));
            out[j] = colors.Color.lerp(start_color, end_color, t);
        }
        
        last_index = end_idx;
    }
    
    // Fill before first index
    const first_color = out[sparse[0].index];
    for (0..sparse[0].index) |i| {
        out[i] = first_color;
    }
    
    // Fill after last index
    const last_idx = sparse[sparse.len - 1].index;
    const last_color = out[last_idx];
    for (@as(usize, last_idx) + 1..256) |i| {
        out[i] = last_color;
    }
}

