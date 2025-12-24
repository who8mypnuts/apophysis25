#version 430
#extension GL_NV_shader_atomic_float : enable

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

#define NUM_PARTICLES 131072

// Transform structure matches Xform in flame.zig
struct Xform {
    float a, b, c, d, e, f;
    float weight;
    float color;
    float linear, sinusoidal, spherical, swirl, horseshoe;
    float polar, handkerchief, heart, disc, spiral;
    float hyperbolic, diamond, ex, julia, bent;
    float padding[1];
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

    for (int i = 0; i < uNumIterations; i++) {
        // Pick transform (Weighted)
        float r_xf = random(rngState);
        int xfIdx = 0;
        float total_weight = 0.0;
        for (int j = 0; j < uNumXforms; j++) total_weight += abs(xforms[j].weight);
        if (total_weight < 0.0001) total_weight = 1.0;
        
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
        if (xf.spherical != 0.0) { float r_pow2 = r2 + 1e-6; vx += xf.spherical * nx / r_pow2; vy += xf.spherical * ny / r_pow2; }
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
        if (xf.bent != 0.0) { if (nx >= 0.0 && ny >= 0.0) { vx += xf.bent * nx; vy += xf.bent * ny; } else if (nx < 0.0 && ny >= 0.0) { vx += xf.bent * 2.0 * nx; vy += xf.bent * ny; } else if (nx >= 0.0 && ny < 0.0) { vx += xf.bent * nx; vy += xf.bent * 0.5 * ny; } else { vx += xf.bent * 2.0 * nx; vy += xf.bent * 0.5 * ny; } }

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
