const std = @import("std");

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,

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

pub const Palette = struct {
    colors: [256]Color,

    pub fn initDefault() Palette {
        var p = Palette{ .colors = undefined };
        // Simple rainbow gradient
        for (0..256) |i| {
            const t = @as(f32, @floatFromInt(i)) / 255.0;
            p.colors[i] = Color{
                .r = 0.5 + 0.5 * std.math.sin(std.math.pi * 2.0 * t),
                .g = 0.5 + 0.5 * std.math.sin(std.math.pi * 2.0 * t + 2.0),
                .b = 0.5 + 0.5 * std.math.sin(std.math.pi * 2.0 * t + 4.0),
            };
        }
        return p;
    }

    pub fn getColor(self: Palette, index: f32) Color {
        // Index is 0.0 - 1.0 (usually)
        // Wrap it
        var idx = index;
        idx = idx - @floor(idx);
        
        const pos = idx * 255.0;
        const i = @as(usize, @intFromFloat(pos));
        const t = pos - @floor(pos);
        
        const c1 = self.colors[i % 256];
        const c2 = self.colors[(i + 1) % 256];
        
        return Color.lerp(c1, c2, t);
    }
};
