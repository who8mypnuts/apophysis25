const std = @import("std");

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,

    pub fn scale(self: Color, scalar: f32) Color {
        return Color{
            .r = self.r * scalar,
            .g = self.g * scalar,
            .b = self.b * scalar,
        };
    }

    pub fn add(self: Color, other: Color) Color {
        return Color{
            .r = self.r + other.r,
            .g = self.g + other.g,
            .b = self.b + other.b,
        };
    }

    pub fn lerp(a: Color, b: Color, t: f32) Color {
        return Color{
            .r = a.r + (b.r - a.r) * t,
            .g = a.g + (b.g - a.g) * t,
            .b = a.b + (b.b - a.b) * t,
        };
    }
};

pub const ColorNode = struct {
    pos: f32, // 0.0 - 1.0
    color: Color,
};

pub const MAX_NODES = 256;

pub const Palette = struct {
    colors: [256]Color,
    nodes: [MAX_NODES]ColorNode,
    num_nodes: u32,

    pub fn initDefault() Palette {
        var p = Palette{
            .colors = undefined,
            .nodes = undefined,
            .num_nodes = 2,
        };
        p.nodes[0] = ColorNode{ .pos = 0.0, .color = Color{ .r = 0, .g = 0, .b = 0 } };
        p.nodes[1] = ColorNode{ .pos = 1.0, .color = Color{ .r = 1, .g = 1, .b = 1 } };

        p.bake(null);
        return p;
    }

    pub fn bake(self: *Palette, tracked_index: ?*i32) void {
        if (self.num_nodes == 0) return;

        // Sort nodes by position (Ensuring selection follows node)
        for (0..self.num_nodes) |i| {
            var min_idx = i;
            for (i + 1..self.num_nodes) |j| {
                if (self.nodes[j].pos < self.nodes[min_idx].pos) {
                    min_idx = j;
                }
            }
            if (min_idx != i) {
                const tmp = self.nodes[i];
                self.nodes[i] = self.nodes[min_idx];
                self.nodes[min_idx] = tmp;

                // Update tracked index
                if (tracked_index) |idx_ptr| {
                    if (idx_ptr.* == @as(i32, @intCast(i))) {
                        idx_ptr.* = @as(i32, @intCast(min_idx));
                    } else if (idx_ptr.* == @as(i32, @intCast(min_idx))) {
                        idx_ptr.* = @as(i32, @intCast(i));
                    }
                }
            }
        }

        for (0..256) |i| {
            const t = @as(f32, @floatFromInt(i)) / 255.0;

            // Find segment
            var found = false;
            if (t <= self.nodes[0].pos) {
                self.colors[i] = self.nodes[0].color;
                found = true;
            } else if (t >= self.nodes[self.num_nodes - 1].pos) {
                self.colors[i] = self.nodes[self.num_nodes - 1].color;
                found = true;
            } else {
                for (0..self.num_nodes - 1) |n| {
                    const n1 = self.nodes[n];
                    const n2 = self.nodes[n+1];
                    if (t >= n1.pos and t <= n2.pos) {
                        const local_t = (t - n1.pos) / (n2.pos - n1.pos);
                        self.colors[i] = Color.lerp(n1.color, n2.color, local_t);
                        found = true;
                        break;
                    }
                }
            }
            if (!found) self.colors[i] = self.nodes[0].color;
        }
    }

    pub fn getColor(self: Palette, index: f32) Color {
        var idx = index;
        idx = idx - @floor(idx);
        const pos = idx * 255.0;
        const i = @as(usize, @intFromFloat(pos));
        const t = pos - @floor(pos);
        const c1 = self.colors[i % 256];
        const c2 = self.colors[(i + 1) % 256];
        return Color.lerp(c1, c2, t);
    }

    pub fn reducePalette(self: *Palette, allocator: std.mem.Allocator, max_nodes: u32) void {
        // If we already have fewer nodes than the target, do nothing
        if (self.num_nodes <= max_nodes or self.num_nodes == 0) return;

        // Create a temporary array to store the reduced palette
        var temp_nodes = std.ArrayListUnmanaged(ColorNode){};
        defer temp_nodes.deinit(allocator);

        // Always keep the first and last nodes
        temp_nodes.append(allocator, self.nodes[0]) catch {};
        for (1..self.num_nodes - 1) |i| {
            const node = self.nodes[i];
            var should_keep = false;

            // Keep this node if it's significantly different from neighbors
            // Check against previous kept node
            if (temp_nodes.items.len > 0) {
                const last_kept = temp_nodes.items[temp_nodes.items.len - 1];
                const diff_r = node.color.r - last_kept.color.r;
                const diff_g = node.color.g - last_kept.color.g;
                const diff_b = node.color.b - last_kept.color.b;
                const color_diff = @sqrt(diff_r * diff_r + diff_g * diff_g + diff_b * diff_b);

                // If the color difference is significant (0.3 in RGB space), keep this node
                if (color_diff > 0.3) {
                    should_keep = true;
                }
            }

            if (should_keep and temp_nodes.items.len < max_nodes - 1) {
                temp_nodes.append(allocator, node) catch {};
            }
        }

        // Always ensure we have the last node
        if (temp_nodes.items.len == 0 or temp_nodes.items[temp_nodes.items.len - 1].pos != self.nodes[self.num_nodes - 1].pos) {
            temp_nodes.append(allocator, self.nodes[self.num_nodes - 1]) catch {};
        }

        // Copy back to the palette nodes array
        const final_count = @min(temp_nodes.items.len, max_nodes);
        for (0..final_count) |i| {
            self.nodes[i] = temp_nodes.items[i];
        }
        self.num_nodes = final_count;
    }
};
