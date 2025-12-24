const std = @import("std");
const variations = @import("variations.zig");
const colors = @import("colors.zig");

pub const Point = struct {
    x: f32,
    y: f32,
    c: f32, // Color coordinate [0, 1]
};

pub const Xform = struct {
    // Affine transform coefficients:
    // x' = ax + cy + e
    // y' = bx + dy + f
    a: f32 = 1.0,
    b: f32 = 0.0,
    c: f32 = 0.0,
    d: f32 = 1.0,
    e: f32 = 0.0,
    f: f32 = 0.0,

    weight: f32 = 1.0,
    color: f32 = 0.0, // Index into the palette [0, 1]
    
    // Variations coefficients
    linear: f32 = 0.0,
    sinusoidal: f32 = 0.0,
    spherical: f32 = 0.0,
    swirl: f32 = 0.0,
    horseshoe: f32 = 0.0,
    polar: f32 = 0.0,
    handkerchief: f32 = 0.0,
    heart: f32 = 0.0,
    disc: f32 = 0.0,
    spiral: f32 = 0.0,
    hyperbolic: f32 = 0.0,
    diamond: f32 = 0.0,
    ex: f32 = 0.0,
    julia: f32 = 0.0,
    bent: f32 = 0.0,

    pub fn apply(self: Xform, p: Point, out: *Point) void {
        // 1. Affine Transform
        const tx = self.a * p.x + self.c * p.y + self.e;
        const ty = self.b * p.x + self.d * p.y + self.f;

        // 2. Variations (Accumulate)
        var vx: f32 = 0.0;
        var vy: f32 = 0.0;

        if (self.linear != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.linear(tx, ty, &dx, &dy);
            vx += dx * self.linear; vy += dy * self.linear;
        }
        if (self.sinusoidal != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.sinusoidal(tx, ty, &dx, &dy);
            vx += dx * self.sinusoidal; vy += dy * self.sinusoidal;
        }
        if (self.spherical != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.spherical(tx, ty, &dx, &dy);
           vx += dx * self.spherical; vy += dy * self.spherical;
        }
        if (self.swirl != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.swirl(tx, ty, &dx, &dy);
           vx += dx * self.swirl; vy += dy * self.swirl;
        }
        if (self.horseshoe != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.horseshoe(tx, ty, &dx, &dy);
           vx += dx * self.horseshoe; vy += dy * self.horseshoe;
        }
        if (self.polar != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.polar(tx, ty, &dx, &dy);
           vx += dx * self.polar; vy += dy * self.polar;
        }
        if (self.handkerchief != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.handkerchief(tx, ty, &dx, &dy);
           vx += dx * self.handkerchief; vy += dy * self.handkerchief;
        }
        if (self.heart != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.heart(tx, ty, &dx, &dy);
           vx += dx * self.heart; vy += dy * self.heart;
        }
        if (self.disc != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.disc(tx, ty, &dx, &dy);
           vx += dx * self.disc; vy += dy * self.disc;
        }
        if (self.spiral != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.spiral(tx, ty, &dx, &dy);
           vx += dx * self.spiral; vy += dy * self.spiral;
        }
        if (self.hyperbolic != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.hyperbolic(tx, ty, &dx, &dy);
           vx += dx * self.hyperbolic; vy += dy * self.hyperbolic;
        }
        if (self.diamond != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.diamond(tx, ty, &dx, &dy);
           vx += dx * self.diamond; vy += dy * self.diamond;
        }
        if (self.ex != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.ex(tx, ty, &dx, &dy);
           vx += dx * self.ex; vy += dy * self.ex;
        }
        if (self.julia != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.julia(tx, ty, &dx, &dy);
           vx += dx * self.julia; vy += dy * self.julia;
        }
        if (self.bent != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           variations.bent(tx, ty, &dx, &dy);
           vx += dx * self.bent; vy += dy * self.bent;
        }

        out.x = vx;
        out.y = vy;
        // out.c will be averaged in the flame iterator
    }
};

pub const Flame = struct {
    xforms: []Xform,
    palette: colors.Palette,
    gamma: f32,
    brightness: f32,
    vibrancy: f32,

    pub fn iterate(self: Flame, p: *Point, rng: std.Random) void {
        // Pick a transform based on weight
        // For now, assuming equal weights or simplified choice
        // TODO: Implement proper weighted random choice
        if (self.xforms.len == 0) return;
        
        const idx = rng.uintLessThan(usize, self.xforms.len);
        const xf = self.xforms[idx];

        var next_p: Point = undefined;
        xf.apply(p.*, &next_p);

        // Color update: c = (c + xf.color) / 2
        next_p.c = (p.c + xf.color) / 2.0;
        
        p.* = next_p;
    }
};
