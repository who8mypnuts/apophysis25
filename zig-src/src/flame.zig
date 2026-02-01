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
    waves: f32 = 0.0,
    fisheye: f32 = 0.0,
    popcorn: f32 = 0.0,
    exponential: f32 = 0.0,
    power: f32 = 0.0,
    cosine: f32 = 0.0,
    rings: f32 = 0.0,
    fan: f32 = 0.0,
    eyefish: f32 = 0.0,
    bubble: f32 = 0.0,
    cylinder: f32 = 0.0,
    noise: f32 = 0.0,
    blur: f32 = 0.0,
    gaussian_blur: f32 = 0.0,
    radial_blur: f32 = 0.0,
    pie: f32 = 0.0,
    ngon: f32 = 0.0,
    curl: f32 = 0.0,
    rectangles: f32 = 0.0,
    tangent: f32 = 0.0,
    square: f32 = 0.0,
    rays: f32 = 0.0,
    blade: f32 = 0.0,
    secant: f32 = 0.0,
    twintrian: f32 = 0.0,
    cross: f32 = 0.0,
    
    // New variations and parameters
    julian: f32 = 0.0,
    julian_power: f32 = 2.0,
    julian_dist: f32 = 1.0,

    // Padding to match GLSL struct (one float)
    padding: f32 = 0.0,

    pub fn apply(self: Xform, p: Point, out: *Point, rng_opt: ?std.Random) void {
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
        if (self.waves != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.waves(tx, ty, &dx, &dy);
            vx += dx * self.waves; vy += dy * self.waves;
        }
        if (self.fisheye != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.fisheye(tx, ty, &dx, &dy);
            vx += dx * self.fisheye; vy += dy * self.fisheye;
        }
        if (self.popcorn != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.popcorn(tx, ty, &dx, &dy);
            vx += dx * self.popcorn; vy += dy * self.popcorn;
        }
        if (self.exponential != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.exponential(tx, ty, &dx, &dy);
            vx += dx * self.exponential; vy += dy * self.exponential;
        }
        if (self.power != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.power(tx, ty, &dx, &dy);
            vx += dx * self.power; vy += dy * self.power;
        }
        if (self.cosine != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.cosine(tx, ty, &dx, &dy);
            vx += dx * self.cosine; vy += dy * self.cosine;
        }
        if (self.rings != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.rings(tx, ty, &dx, &dy, 1.0);
            vx += dx * self.rings; vy += dy * self.rings;
        }
        if (self.fan != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.fan(tx, ty, &dx, &dy, 1.0, 0.0);
            vx += dx * self.fan; vy += dy * self.fan;
        }
        if (self.eyefish != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.eyefish(tx, ty, &dx, &dy);
            vx += dx * self.eyefish; vy += dy * self.eyefish;
        }
        if (self.bubble != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.bubble(tx, ty, &dx, &dy);
            vx += dx * self.bubble; vy += dy * self.bubble;
        }
        if (self.cylinder != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.cylinder(tx, ty, &dx, &dy);
            vx += dx * self.cylinder; vy += dy * self.cylinder;
        }
        if (self.noise != 0) {
            const r_val = if (rng_opt) |r| r.float(f32) - 0.5 else 0.0;
            vx += self.noise * tx * r_val;
            vy += self.noise * ty * r_val; 
        }
        if (self.blur != 0) {
            const ang = if (rng_opt) |r| r.float(f32) * 6.283 else 0.0;
            const rad = if (rng_opt) |r| r.float(f32) else 0.0;
            vx += self.blur * rad * @cos(ang);
            vy += self.blur * rad * @sin(ang);
        }
        if (self.gaussian_blur != 0) {
            const ang = if (rng_opt) |r| r.float(f32) * 6.283 else 0.0;
            const rad = if (rng_opt) |r| (r.float(f32) + r.float(f32) + r.float(f32) + r.float(f32)) * 0.25 else 0.0;
            vx += self.gaussian_blur * rad * @cos(ang);
            vy += self.gaussian_blur * rad * @sin(ang);
        }
        if (self.radial_blur != 0) {
           const r = @sqrt(tx*tx + ty*ty);
           const theta = std.math.atan2(ty, tx);
           const ang = theta + (if (rng_opt) |r_rng| r_rng.float(f32) - 0.5 else 0.0) * 0.5;
           vx += self.radial_blur * r * @cos(ang);
           vy += self.radial_blur * r * @sin(ang);
        }
        if (self.pie != 0) {
             const slices: f32 = 3.0;
             const r = @sqrt(tx*tx + ty*ty);
             const t = @floor((if (rng_opt) |rnd| rnd.float(f32) else 0.5) * slices + 0.5) * 6.283 / slices;
             vx += self.pie * r * @cos(t);
             vy += self.pie * r * @sin(t);
        }
        if (self.ngon != 0) {
            const n_count: f32 = 5.0;
            const period = 6.283 / n_count;
            const r_val = @sqrt(tx*tx + ty*ty);
            const theta = std.math.atan2(ty, tx);
            const phi = theta - period * @floor(theta / period) - period * 0.5;
            const factor = (@cos(period * 0.5) / @cos(phi));
            vx += self.ngon * factor * r_val * @cos(theta);
            vy += self.ngon * factor * r_val * @sin(theta);
        }
        if (self.curl != 0) {
            const c1: f32 = 1.0;
            const c2: f32 = 1.0;
            const t1 = 1.0 + c1 * tx + c2 * (tx * tx - ty * ty);
            const t2 = c1 * ty + 2.0 * c2 * tx * ty;
            const det = t1 * t1 + t2 * t2;
            vx += self.curl * (tx * t1 + ty * t2) / det;
            vy += self.curl * (ty * t1 - tx * t2) / det;
        }
        if (self.rectangles != 0) {
            const x_r = @floor(tx + 0.5);
            const y_r = @floor(ty + 0.5);
            vx += self.rectangles * (2.0 * x_r - tx);
            vy += self.rectangles * (2.0 * y_r - ty);
        }
        if (self.square != 0) {
            const r1 = if (rng_opt) |r| r.float(f32) - 0.5 else 0.0;
            const r2 = if (rng_opt) |r| r.float(f32) - 0.5 else 0.0;
            vx += self.square * r1;
            vy += self.square * r2;
        }
        if (self.tangent != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.tangent(tx, ty, &dx, &dy);
            vx += dx * self.tangent; vy += dy * self.tangent;
        }
        if (self.square != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.square(tx, ty, &dx, &dy);
            vx += dx * self.square; vy += dy * self.square;
        }
        if (self.rays != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.rays(tx, ty, &dx, &dy);
            vx += dx * self.rays; vy += dy * self.rays;
        }
        if (self.blade != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.blade(tx, ty, &dx, &dy);
            vx += dx * self.blade; vy += dy * self.blade;
        }
        if (self.secant != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.secant(tx, ty, &dx, &dy);
            vx += dx * self.secant; vy += dy * self.secant;
        }
        if (self.julian != 0) {
           var dx: f32 = 0; var dy: f32 = 0;
           // We need RNG for Julian. If not provided, use deterministic (0)
           var rnd: f32 = 0.0;
           if (rng_opt) |rng| {
               rnd = rng.float(f32);
           }
           variations.julian(tx, ty, &dx, &dy, self.julian_power, self.julian_dist, rnd);
           vx += dx * self.julian; vy += dy * self.julian;
        }
        if (self.twintrian != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.twintrian(tx, ty, &dx, &dy);
            vx += dx * self.twintrian; vy += dy * self.twintrian;
        }
        if (self.cross != 0) {
            var dx: f32 = 0; var dy: f32 = 0;
            variations.crossVariation(tx, ty, &dx, &dy);
            vx += dx * self.cross; vy += dy * self.cross;
        }

        out.x = vx;
        out.y = vy;
        // out.c will be averaged in the flame iterator
    }

    pub fn rotate(self: *Xform, angle_degrees: f32) void {
        const rad = angle_degrees * std.math.pi / 180.0;
        const c = @cos(rad);
        const s = @sin(rad);

        // Apply rotation matrix [ c -s ]
        //                       [ s  c ]
        // to the affine matrix  [ a c_coef ] (using c_coef because c is taken)
        //                       [ b d      ]

        // New basis vectors:
        // X' = X * cos - Y * sin
        // Y' = X * sin + Y * cos
        
        // Wait, standard affine composition: 
        // We want to rotate the current transform.
        // If we view the transform as a coordinate frame (a,b) and (c,d),
        // we rotate these vectors.
        
        const new_a = self.a * c - self.c * s;
        const new_b = self.b * c - self.d * s;
        const new_c = self.a * s + self.c * c;
        const new_d = self.b * s + self.d * c;

        self.a = new_a;
        self.b = new_b;
        self.c = new_c;
        self.d = new_d;
    }
};

pub const Flame = struct {
    xforms: []Xform,
    palette: colors.Palette,
    gamma: f32,
    brightness: f32,
    vibrancy: f32,

    pub fn iterate(self: Flame, p: *Point, rng: std.Random) void {
        if (self.xforms.len == 0) return;
        
        var total_weight: f32 = 0;
        for (self.xforms) |xf| {
            total_weight += @abs(xf.weight);
        }
        
        if (total_weight < 0.0001) {
            // Fallback to uniform if all weights are zero
            const idx = rng.uintLessThan(usize, self.xforms.len);
            const xf = self.xforms[idx];
            var next_p: Point = undefined;
            xf.apply(p.*, &next_p, rng);
            next_p.c = (p.c + xf.color) / 2.0;
            p.* = next_p;
            return;
        }

        const r = rng.float(f32) * total_weight;
        var cumulative: f32 = 0;
        for (self.xforms) |xf| {
            cumulative += @abs(xf.weight);
            if (r <= cumulative) {
                var next_p: Point = undefined;
                xf.apply(p.*, &next_p, rng);
                next_p.c = (p.c + xf.color) / 2.0;
                p.* = next_p;
                return;
            }
        }
    }
};
