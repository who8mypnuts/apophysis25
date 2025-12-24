const std = @import("std");

pub fn linear(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    out_x.* = x;
    out_y.* = y;
}

pub fn sinusoidal(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    out_x.* = std.math.sin(x);
    out_y.* = std.math.sin(y);
}

pub fn spherical(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r2 = x * x + y * y;
    if (r2 > 1e-6) {
        out_x.* = x / r2;
        out_y.* = y / r2;
    } else {
        out_x.* = 0;
        out_y.* = 0;
    }
}

pub fn swirl(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r2 = x * x + y * y;
    const s = std.math.sin(r2);
    const c = std.math.cos(r2);
    out_x.* = x * s - y * c;
    out_y.* = x * c + y * s;
}

pub fn horseshoe(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    if (r < 1e-6) {
        out_x.* = 0;
        out_y.* = 0;
        return;
    }
    out_x.* = (x - y) * (x + y) / r; // (x^2 - y^2) / r
    out_y.* = 2.0 * x * y / r;
}

pub fn polar(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    out_x.* = theta / std.math.pi;
    out_y.* = r - 1.0;
}

pub fn handkerchief(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    out_x.* = r * std.math.sin(theta + r);
    out_y.* = r * std.math.cos(theta - r);
}

pub fn heart(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    out_x.* = r * std.math.sin(theta * r);
    out_y.* = -r * std.math.cos(theta * r);
}

pub fn disc(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    const pi = std.math.pi;
    out_x.* = theta / pi * std.math.sin(pi * r);
    out_y.* = theta / pi * std.math.cos(pi * r);
}

pub fn spiral(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    if (r < 1e-6) {
        out_x.* = 0;
        out_y.* = 0;
        return;
    }
    out_x.* = (std.math.cos(theta) + std.math.sin(r)) / r;
    out_y.* = (std.math.sin(theta) - std.math.cos(r)) / r;
}

pub fn hyperbolic(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    if (r < 1e-6) {
        out_x.* = 0;
        out_y.* = 0;
        return;
    }
    out_x.* = std.math.sin(theta) / r;
    out_y.* = r * std.math.cos(theta);
}

pub fn diamond(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    out_x.* = std.math.sin(theta) * std.math.cos(r);
    out_y.* = std.math.cos(theta) * std.math.sin(r);
}

pub fn ex(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    const r = std.math.sqrt(x * x + y * y);
    const theta = std.math.atan2(y, x);
    const p0 = std.math.sin(theta + r);
    const p0_3 = p0 * p0 * p0;
    const p1 = std.math.cos(theta - r);
    const p1_3 = p1 * p1 * p1;
    
    out_x.* = r * (p0_3 + p1_3);
    out_y.* = r * (p0_3 - p1_3);
}

pub fn julia(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    // Note: Julia usually requires random choice between sqrt(r) and -sqrt(r)
    // For standard flame algorithm, we often use rng here, but variations signature usually doesn't take rng.
    // Apophysis implementation:
    // r = sqrt(r)
    // theta = theta / 2 + random_bit * pi
    // Since we don't have RNG here, this variation is tricky in this context. 
    // Usually variations that need randomness take context.
    // For now, let's implement deterministic part or skip.
    // Let's implement a deterministic "Julia" (fixed choice) or proper one if we change signature.
    // For this rewrite, I will skip Julia for now or just do one branch.
    
    // Simplification: just one branch (no split)
    const r = std.math.sqrt(std.math.sqrt(x * x + y * y));
    const theta = std.math.atan2(y, x) * 0.5;
    out_x.* = r * std.math.cos(theta);
    out_y.* = r * std.math.sin(theta);
}

pub fn bent(x: f32, y: f32, out_x: *f32, out_y: *f32) void {
    if (x >= 0.0 and y >= 0.0) {
        out_x.* = x;
        out_y.* = y;
    } else if (x < 0.0 and y >= 0.0) {
        out_x.* = 2.0 * x;
        out_y.* = y;
    } else if (x >= 0.0 and y < 0.0) {
        out_x.* = x;
        out_y.* = y / 2.0;
    } else {
        out_x.* = 2.0 * x;
        out_y.* = y / 2.0;
    }
}
