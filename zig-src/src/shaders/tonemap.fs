#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0; // This will be our high-precision histogram texture (RGBA32F)
uniform float uGamma;
uniform float uBrightness;
uniform float uVibrancy;
uniform float uLogMaxHits;

out vec4 finalColor;

void main()
{
    vec4 hist = texture(texture0, fragTexCoord);
    float hits = hist.r; // R32F format: hits are in the R channel

    if (hits <= 0.0) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Default color (Cyan/White)
    vec3 avgColor = vec3(0.5, 0.8, 1.0);

    // Density estimation (Log scale)
    float logHits = log(1.0 + hits) / log(10.0); // log10(1 + hits)
    float alpha = logHits / uLogMaxHits;   // [0, 1] density

    // Tone Map
    float tmAlpha = pow(alpha, 1.0 / uGamma) * uBrightness * uVibrancy;
    vec3 color = avgColor * tmAlpha;

    finalColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
