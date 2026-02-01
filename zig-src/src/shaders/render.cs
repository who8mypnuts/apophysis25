#version 430
#extension GL_NV_shader_atomic_float : enable

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

#define NUM_PARTICLES 131072

// Transform structure matches Xform in flame.zig
struct Xform {
    float a, b, c, d, e, f;
    float weight;
    float color;
    float linear, sinusoidal, spherical, swirl;
    float horseshoe, polar, handkerchief, heart;
    float disc, spiral, hyperbolic, diamond;
    float ex, julia, bent, waves;
    float fisheye, popcorn, exponential, power;
    float cosine, rings, fan, eyefish;
    float bubble, cylinder, noise, blur;
    float gaussian_blur, radial_blur, pie, ngon;
    float curl, rectangles, tangent, square;
    float rays, blade, secant, twintrian;
    float cross;
    
    // New variations and parameters
    float julian, julian_power, julian_dist;
    
    // Padding adjusted: 
    // We added 3 floats. Original padding was 3 floats.
    // 3 - 3 = 0.
    // So padding array can be removed or size 0.
    // However, Zig added padding: [0]f32.
    // GLSL alignment: struct size must be multiple of 16 bytes (vec4) or std430 rules.
    // Previous: 6 + 1 + 1 + 27 variations weights + 3 padding = 38 floats. Not aligned?
    // Let's count floats.
    // a..f: 6
    // weight: 1
    // color: 1
    // vars (linear..cross): 41 lines?
    // Let's check original.
    // 41 vars.
    // Total: 6+1+1+41 = 49.
    // +3 padding = 52. 52 floats = 208 bytes. 208/16 = 13 vectors. Aligned.
    // Now we add 3 floats (julian, power, dist).
    // Total 55 floats.
    // Need 1 float padding to reach 56 (multiple of 4 floats / 16 bytes).
    float padding;
};

struct Point {
    float x, y, c;
    float padding;
};

// SSBOs
layout(std430, binding = 0) buffer TransformBuffer {
    Xform xforms[];
};

layout(std430, binding = 1) buffer PointBuffer {
    Point points[];
};

// Histogram structure
struct Hist {
    float r, g, b, c; // Color + Counter
};

layout(std430, binding = 2) buffer HistogramBuffer {
    Hist histogram[];
};

// Palette (SSBO)
layout(std430, binding = 3) buffer PaletteBuffer {
    vec4 palette[256];
};

// Uniforms
uniform int uNumXforms;
uniform int uNumIterations;
uniform float uScale;
uniform int uWidth;
uniform int uHeight;
uniform float uSeed;

// Quick RNG
uint hash(uint x) {
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return x;
}

float random(inout uint state) {
    state = hash(state);
    return float(state) / 4294967296.0;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= NUM_PARTICLES) return;
    
    uint rngState = uint(uSeed) + idx * 7919;

    Point p = points[idx];
    float cx = float(uWidth) / 2.0;
    float cy = float(uHeight) / 2.0;

    float total_weight = 0.0;
    for (int j = 0; j < uNumXforms; j++) total_weight += abs(xforms[j].weight);
    if (total_weight < 0.0001) total_weight = 1.0;

    for (int i = 0; i < uNumIterations; i++) {
        // Pick transform (Weighted)
        float r_xf = random(rngState);
        int xfIdx = 0;
        
        float cumulative = 0.0;
        for (int j = 0; j < uNumXforms; j++) {
            cumulative += abs(xforms[j].weight) / total_weight;
            if (r_xf <= cumulative) {
                xfIdx = j;
                break;
            }
        }
        Xform xf = xforms[xfIdx];

        // Apply Affine (MATCH ZIG MATH: x' = ax + cy + e, y' = bx + dy + f)
        float nx = xf.a * p.x + xf.c * p.y + xf.e;
        float ny = xf.b * p.x + xf.d * p.y + xf.f;

        // Apply Variations
        float vx = 0.0;
        float vy = 0.0;
        
        float r2 = nx*nx + ny*ny;
        float r = sqrt(r2 + 1e-6);
        float theta = atan(ny, nx);

        // Variations logic
        if (xf.linear != 0.0) { vx += xf.linear * nx; vy += xf.linear * ny; }
        if (xf.sinusoidal != 0.0) { vx += xf.sinusoidal * sin(nx); vy += xf.sinusoidal * sin(ny); }
        if (xf.spherical != 0.0) { vx += xf.spherical * nx / r2; vy += xf.spherical * ny / r2; }
        if (xf.swirl != 0.0) { float s = sin(r2); float c = cos(r2); vx += xf.swirl * (nx*s - ny*c); vy += xf.swirl * (nx*c + ny*s); }
        if (xf.horseshoe != 0.0) { vx += xf.horseshoe * (nx - ny) * (nx + ny) / r; vy += xf.horseshoe * 2.0 * nx * ny / r; }
        if (xf.polar != 0.0) { vx += xf.polar * theta / 3.14159; vy += xf.polar * (r - 1.0); }
        if (xf.handkerchief != 0.0) { vx += xf.handkerchief * r * sin(theta + r); vy += xf.handkerchief * r * cos(theta - r); }
        if (xf.heart != 0.0) { vx += xf.heart * r * sin(theta * r); vy += xf.heart * r * -cos(theta * r); }
        if (xf.disc != 0.0) { float f_disc = 3.14159 * r; vx += xf.disc * theta / 3.14159 * sin(f_disc); vy += xf.disc * theta / 3.14159 * cos(f_disc); }
        if (xf.spiral != 0.0) { vx += xf.spiral * (cos(theta) + sin(r)) / r; vy += xf.spiral * (sin(theta) - cos(r)) / r; }
        if (xf.hyperbolic != 0.0) { vx += xf.hyperbolic * sin(theta) / r; vy += xf.hyperbolic * r * cos(theta); }
        if (xf.diamond != 0.0) { vx += xf.diamond * sin(theta) * cos(r); vy += xf.diamond * cos(theta) * sin(r); }
        if (xf.ex != 0.0) { float p0 = sin(theta + r); float p1 = cos(theta - r); vx += xf.ex * r * (p0*p0*p0 + p1*p1*p1); vy += xf.ex * r * (p0*p0*p0 - p1*p1*p1); }
        if (xf.julia != 0.0) { float r_sqrt = sqrt(r); float theta_2 = theta * 0.5; vx += xf.julia * r_sqrt * cos(theta_2); vy += xf.julia * r_sqrt * sin(theta_2); }
        if (xf.bent != 0.0) { if (nx >= 0.0 && ny >= 0.0) { vx += xf.bent * nx; vy += xf.bent * ny; } else if (nx < 0.0 && ny >= 0.0) { vx += xf.bent * 2.0 * nx; vy += xf.bent * ny; } else if (nx >= 0.0 && ny < 0.0) { vx += xf.bent * nx; vy += xf.bent * 0.5 * ny; } else { vx += xf.bent * 2.0 * nx; vy += xf.bent * 0.5 * ny; } }
        
        if (xf.waves != 0.0) { vx += xf.waves * (nx + 0.5 * sin(ny)); vy += xf.waves * (ny + 0.5 * sin(nx)); }
        if (xf.fisheye != 0.0) { float factor = 2.0 / (r + 1.0); vx += xf.fisheye * factor * ny; vy += xf.fisheye * factor * nx; }
        if (xf.popcorn != 0.0) { vx += xf.popcorn * (nx + 0.05 * sin(tan(3.0 * ny))); vy += xf.popcorn * (ny + 0.05 * sin(tan(3.0 * nx))); }
        if (xf.exponential != 0.0) { float factor = exp(nx - 1.0); vx += xf.exponential * factor * cos(3.14159 * ny); vy += xf.exponential * factor * sin(3.14159 * ny); }
        if (xf.power != 0.0) { float p_pow = pow(r, sin(theta)); vx += xf.power * p_pow * cos(theta); vy += xf.power * p_pow * sin(theta); }
        if (xf.cosine != 0.0) { vx += xf.cosine * cos(3.14159 * nx) * cosh(ny); vy += xf.cosine * -sin(3.14159 * nx) * sinh(ny); }
        if (xf.rings != 0.0) { float c2 = 1.0; float factor = mod(r + c2, 2.0 * c2) - c2 + r * (1.0 - c2); vx += xf.rings * factor * cos(theta); vy += xf.rings * factor * sin(theta); }
        if (xf.fan != 0.0) { float c = 1.0; float f = 0.0; float t = 3.14159 * c * c; float angle = (mod(theta + f, 2.0 * t) > t) ? theta - t : theta + t; vx += xf.fan * r * cos(angle); vy += xf.fan * r * sin(angle); }
        if (xf.eyefish != 0.0) { float factor = 2.0 / (r + 1.0); vx += xf.eyefish * factor * nx; vy += xf.eyefish * factor * ny; }
        if (xf.bubble != 0.0) { float factor = 4.0 / (r2 + 4.0); vx += xf.bubble * factor * nx; vy += xf.bubble * factor * ny; }
        if (xf.cylinder != 0.0) { vx += xf.cylinder * sin(nx); vy += xf.cylinder * ny; }
        if (xf.noise != 0.0) { float r_nse = random(rngState); vx += xf.noise * nx * r_nse; vy += xf.noise * ny * r_nse; }
        if (xf.blur != 0.0) { float ang = random(rngState) * 6.283; float rad = random(rngState); vx += xf.blur * rad * cos(ang); vy += xf.blur * rad * sin(ang); }
        if (xf.gaussian_blur != 0.0) { float ang = random(rngState) * 6.283; float rad = (random(rngState) + random(rngState) + random(rngState) + random(rngState)) * 0.25; vx += xf.gaussian_blur * rad * cos(ang); vy += xf.gaussian_blur * rad * sin(ang); }
        if (xf.radial_blur != 0.0) { float ang = theta + (random(rngState)-0.5)*0.5; vx += xf.radial_blur * r * cos(ang); vy += xf.radial_blur * r * sin(ang); }
        if (xf.pie != 0.0) { float slices = 3.0; float t = floor(random(rngState)*slices + 0.5) * 6.283/slices; vx += xf.pie * r * cos(t); vy += xf.pie * r * sin(t); }
        if (xf.ngon != 0.0) { float n = 5.0; float p = 6.283/n; float phi = mod(theta, p) - p*0.5; float factor = (cos(p*0.5) / cos(phi)); vx += xf.ngon * factor * r * cos(theta); vy += xf.ngon * factor * r * sin(theta); }
        if (xf.curl != 0.0) { float c1 = 1.0; float c2 = 1.0; float t1 = 1.0 + c1*nx + c2*(nx*nx - ny*ny); float t2 = c1*ny + 2.0*c2*nx*ny; float det = t1*t1 + t2*t2; vx += xf.curl * (nx*t1 + ny*t2)/det; vy += xf.curl * (ny*t1 - nx*t2)/det; }
        if (xf.rectangles != 0.0) { float x_r = floor(nx + 0.5); float y_r = floor(ny + 0.5); vx += xf.rectangles * (2.0*x_r - nx); vy += xf.rectangles * (2.0*y_r - ny); }
        if (xf.tangent != 0.0) { vx += xf.tangent * sin(nx) / cos(ny); vy += xf.tangent * tan(ny); }
        if (xf.square != 0.0) { vx += xf.square * (random(rngState) - 0.5); vy += xf.square * (random(rngState) - 0.5); }
        if (xf.rays != 0.0) { float factor = cos(r2) / r2; vx += xf.rays * factor * nx; vy += xf.rays * factor * ny; }
        if (xf.blade != 0.0) { float s = sin(r); vx += xf.blade * nx * (cos(s) + sin(s)); vy += xf.blade * nx * (cos(s) - sin(s)); }
        if (xf.secant != 0.0) { float factor = 1.0 / cos(r); vx += xf.secant * nx; vy += xf.secant * ny * factor; }
        if (xf.twintrian != 0.0) { float s = sin(r); float c = cos(r); vx += xf.twintrian * nx * s * c; vy += xf.twintrian * nx * (s - c); }
        if (xf.cross != 0.0) { float factor = sqrt(1.0 / (pow(nx*nx - ny*ny, 2.0) + 1e-6)); vx += xf.cross * nx * factor; vy += xf.cross * ny * factor; }
        
        if (xf.julian != 0.0) {
             float absN = abs(xf.julian_power);
             if (absN > 0.001) {
                 float rnd = random(rngState);
                 float branch = floor(rnd * absN);
                 float a = (atan(ny, nx) + 2.0 * 3.14159265 * branch) / xf.julian_power;
                 float r_2 = nx*nx + ny*ny;
                 float exponent = xf.julian_dist / xf.julian_power / 2.0;
                 float r_val = pow(r_2, exponent);
                 vx += xf.julian * r_val * cos(a);
                 vy += xf.julian * r_val * sin(a);
             } else {
                 vx += xf.julian * nx;
                 vy += xf.julian * ny;
             }
        }

        // Default to Linear if no variations active
        if (vx == 0.0 && vy == 0.0) { vx = nx; vy = ny; }

        p.x = vx;
        p.y = vy;
        p.c = (p.c + xf.color) * 0.5;

        // Map to screen
        int sx = int(p.x * uScale + cx);
        int sy = int(p.y * uScale + cy);

            if (sx >= 0 && sx < uWidth && sy >= 0 && sy < uHeight) {
                uint h_idx = uint(sy * uWidth + sx);
                
                // Store accumulated color index and hit count
                atomicAdd(histogram[h_idx].r, p.c); // Use 'r' as sum_c
                atomicAdd(histogram[h_idx].c, 1.0); // Use 'c' as hits
            }
    }

    // Safety: prevent NaNs from ruining the PointBuffer
    if (isnan(p.x) || isinf(p.x)) p.x = 0.0;
    if (isnan(p.y) || isinf(p.y)) p.y = 0.0;
    
    points[idx] = p;
}
