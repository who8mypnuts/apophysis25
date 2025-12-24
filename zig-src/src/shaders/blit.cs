#version 430

layout(local_size_x = 16, local_size_y = 16) in;

struct Hist {
    float r, g, b, c;
};

layout(std430, binding = 2) buffer HistogramBuffer {
    Hist histogram[];
};

layout(rgba8, binding = 0) uniform image2D outTex;

uniform float uGamma;
uniform float uBrightness;
uniform float uVibrancy;
uniform float uMaxHits;

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(outTex);
    if (pixel.x >= size.x || pixel.y >= size.y) return;

    uint idx = uint(pixel.y * size.x + pixel.x);
    Hist h = histogram[idx];

    if (h.c <= 0.0) {
        imageStore(outTex, pixel, vec4(0, 0, 0, 1));
        return;
    }

    // Average color
    vec3 color = vec3(h.r, h.g, h.b) / h.c;
    
    // Density estimation (log scale)
    float logHits = log(1.0 + h.c) / log(10.0);
    float logMax = log(1.0 + uMaxHits) / log(10.0);
    if (logMax < 0.1) logMax = 1.0;
    
    float alpha = clamp(logHits / logMax, 0.0, 1.0);
    
    // Tonemapping
    vec3 finalColor = color * pow(alpha, 1.0 / uVibrancy) * uBrightness;
    finalColor = pow(finalColor, vec3(1.0 / uGamma));

    imageStore(outTex, pixel, vec4(finalColor, 1.0));
}
