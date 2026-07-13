#pragma language glsl3

vec3 AcesFilmicTonemap(vec3 Color)
{
    float A = 2.51;
    float B = 0.03;
    float C = 2.43;
    float D = 0.59;
    float E = 0.14;
    return clamp((Color * (A * Color + B)) / (Color * (C * Color + D) + E), 0.0, 1.0);
}

vec4 effect(vec4 GlobalColor, sampler2D CurrentTexture, vec2 TexCoord, vec2 ScreenPos)
{
    vec3 HdrColor = texture(CurrentTexture, TexCoord).rgb;
    HdrColor *= 1.2;
    vec3 MappedColor = AcesFilmicTonemap(HdrColor);
    return vec4(pow(MappedColor, vec3(1.0 / 2.2)), 1.0);
}