#pragma language glsl3

#define MAX_DDA_STEPS 2048
#define SHADOW_RAY_STEPS 128
#define REFLECTION_DDA_STEPS 128
#define INF 1e30

#define COARSE_SWITCH_DISTANCE 512.0
#define COARSE_MAX_STEPS 512

#define COARSE_BLEND_BAND 96.0

uniform vec3 CameraPosition;
uniform vec3 CameraRotation;
uniform vec2 ScreenDimensions;

uniform sampler3D VoxelGrid;
uniform sampler3D MaterialGrid;
uniform sampler3D BrickGrid;
uniform float BrickSize;
uniform vec3 BrickResolution;
uniform vec3 GridResolution;
uniform vec3 LoadedMin;
uniform vec3 LoadedMax;

uniform vec3 SunDirection;
uniform vec3 SunColor;
uniform float VoxelSize;
uniform float ChunkBaseY;

uniform sampler2D ChunkStateMap;
uniform float TextureChunkSpan;

vec3 InvGridResolution()  { return 1.0 / GridResolution; }
vec3 InvBrickResolution() { return 1.0 / BrickResolution; }

struct HitResult
{
    bool Hit;
    vec3 Albedo;
    vec3 Normal;
    float Roughness;
    float Reflectivity;
    float Refractivity;
    float Opacity;
    vec3 HitPos;
    float Dist;
};

bool IsChunkValid(vec3 MapPos)
{
    vec2 ChunkCoord = floor((MapPos.xz * VoxelSize) / (16.0 * VoxelSize));
    vec2 StateTc = (mod(ChunkCoord, TextureChunkSpan) + 0.5) / TextureChunkSpan;
    vec4 State = texture(ChunkStateMap, StateTc);
    return abs(State.r - ChunkCoord.x) < 0.1 && abs(State.g - ChunkCoord.y) < 0.1;
}

vec3 GetVoxelTc(vec3 MapPos, vec3 InvGridRes)
{
    return (MapPos + 0.5) * InvGridRes;
}

bool IsBrickOccupied(vec3 BrickCoord, vec3 InvBrickRes)
{
    vec3 Tc = (mod(BrickCoord, BrickResolution) + 0.5) * InvBrickRes;
    return texture(BrickGrid, Tc).r > 0.5;
}

vec3 SkyColor(vec3 Dir, bool IncludeSunDisc)
{
    vec3 D = normalize(Dir);
    float SunDot = max(dot(D, normalize(SunDirection)), 0.0);
    float Y = clamp(D.y, -1.0, 1.0);
    vec3 Zenith = mix(vec3(0.05, 0.15, 0.4), vec3(0.01, 0.05, 0.2), max(Y, 0.0));
    vec3 Horizon = mix(vec3(0.4, 0.5, 0.6), vec3(0.7, 0.55, 0.4), pow(SunDot, 4.0));
    vec3 Ground = vec3(0.01, 0.008, 0.005);
    vec3 Sky = mix(Horizon, Zenith, smoothstep(-0.1, 1.0, Y));
    if (Y < 0.0) Sky = mix(Horizon, Ground, clamp(-Y * 8.0, 0.0, 1.0));
    float AtmosphereGlow = exp(-(1.0 - SunDot) * 12.0) * 1.5;
    vec3 TotalSky = Sky + SunColor * AtmosphereGlow;
    if (IncludeSunDisc)
    {
        float Disc = smoothstep(0.9996, 1.0, SunDot);
        TotalSky += SunColor * Disc * 45.0;
    }
    return max(TotalSky, vec3(0.0));
}

HitResult TraceBrickCoarse(vec3 RayOrigin, vec3 RayDir, vec3 StartMapPos)
{
    HitResult Result;
    Result.Hit = false;

    vec3 InvGridRes = InvGridResolution();
    vec3 InvBrickRes = InvBrickResolution();

    vec3 ScaledOrigin = (RayOrigin / VoxelSize) / BrickSize;
    vec3 BrickMapPos = floor(StartMapPos / BrickSize + 1e-5);
    vec3 StepDir = sign(RayDir);
    vec3 DeltaDist = (1.0 / max(abs(RayDir), 1e-6));
    vec3 SideDist = vec3(
        (StepDir.x > 0.0) ? (BrickMapPos.x + 1.0 - ScaledOrigin.x) * DeltaDist.x : (ScaledOrigin.x - BrickMapPos.x) * DeltaDist.x,
        (StepDir.y > 0.0) ? (BrickMapPos.y + 1.0 - ScaledOrigin.y) * DeltaDist.y : (ScaledOrigin.y - BrickMapPos.y) * DeltaDist.y,
        (StepDir.z > 0.0) ? (BrickMapPos.z + 1.0 - ScaledOrigin.z) * DeltaDist.z : (ScaledOrigin.z - BrickMapPos.z) * DeltaDist.z
    );
    vec3 Mask = vec3(0.0);

    int Step = 0;
    while (Step < COARSE_MAX_STEPS)
    {
        vec3 VoxelMapPos = BrickMapPos * BrickSize;

        if (VoxelMapPos.y < 0.0 || VoxelMapPos.y >= GridResolution.y ||
            VoxelMapPos.x < LoadedMin.x || VoxelMapPos.x >= LoadedMax.x ||
            VoxelMapPos.z < LoadedMin.z || VoxelMapPos.z >= LoadedMax.z) break;

        if (IsBrickOccupied(BrickMapPos, InvBrickRes))
        {
            
            float Dist = dot(SideDist - DeltaDist, Mask) * BrickSize * VoxelSize;

            vec3 EntryVoxel = floor((RayOrigin + RayDir * (Dist + 0.5 * VoxelSize)) / VoxelSize);

            if (EntryVoxel.x >= LoadedMin.x && EntryVoxel.x < LoadedMax.x &&
                EntryVoxel.z >= LoadedMin.z && EntryVoxel.z < LoadedMax.z &&
                EntryVoxel.y >= 0.0 && EntryVoxel.y < GridResolution.y &&
                IsChunkValid(EntryVoxel))
            {
                vec3 Tc = GetVoxelTc(EntryVoxel, InvGridRes);
                vec4 Vox = textureLod(VoxelGrid, Tc, 0.0);

                if (Vox.a > 0.0)
                {
                    vec4 Mat = textureLod(MaterialGrid, Tc, 0.0);
                    Result.Hit = true;
                    Result.Albedo = Vox.rgb;
                    Result.Normal = -StepDir * Mask;
                    Result.Roughness = clamp(Mat.r, 0.04, 1.0);
                    Result.Reflectivity = clamp(Mat.g, 0.0, 1.0);
                    Result.Refractivity = clamp(Mat.b, 0.0, 1.0);
                    Result.Opacity = Vox.a;
                    Result.HitPos = RayOrigin + RayDir * Dist;
                    Result.Dist = Dist;
                    return Result;
                }
            }
        }

        if (SideDist.x < SideDist.y)
        {
            if (SideDist.x < SideDist.z) { SideDist.x += DeltaDist.x; BrickMapPos.x += StepDir.x; Mask = vec3(1.0, 0.0, 0.0); }
            else { SideDist.z += DeltaDist.z; BrickMapPos.z += StepDir.z; Mask = vec3(0.0, 0.0, 1.0); }
        }
        else
        {
            if (SideDist.y < SideDist.z) { SideDist.y += DeltaDist.y; BrickMapPos.y += StepDir.y; Mask = vec3(0.0, 1.0, 0.0); }
            else { SideDist.z += DeltaDist.z; BrickMapPos.z += StepDir.z; Mask = vec3(0.0, 0.0, 1.0); }
        }
        Step++;
    }

    return Result;
}

HitResult TraceVoxel(vec3 RayOrigin, vec3 RayDir, int MaxSteps, float IgnoreOpacity)
{
    HitResult Result;
    Result.Hit = false;

    vec3 InvGridRes = InvGridResolution();
    vec3 InvBrickRes = InvBrickResolution();

    vec3 ScaledOrigin = RayOrigin / VoxelSize;
    vec3 MapPos = floor(ScaledOrigin + 1e-5);
    vec3 StepDir = sign(RayDir);
    vec3 InvAbsDir = 1.0 / max(abs(RayDir), 1e-6);
    vec3 DeltaDist = InvAbsDir;
    vec3 SideDist = vec3(
        (StepDir.x > 0.0) ? (MapPos.x + 1.0 - ScaledOrigin.x) * DeltaDist.x : (ScaledOrigin.x - MapPos.x) * DeltaDist.x,
        (StepDir.y > 0.0) ? (MapPos.y + 1.0 - ScaledOrigin.y) * DeltaDist.y : (ScaledOrigin.y - MapPos.y) * DeltaDist.y,
        (StepDir.z > 0.0) ? (MapPos.z + 1.0 - ScaledOrigin.z) * DeltaDist.z : (ScaledOrigin.z - MapPos.z) * DeltaDist.z
    );
    vec3 Mask = vec3(0.0);

    vec3 LastBrickCoord = vec3(1e30);
    bool LastBrickOccupied = false;

    int Step = 0;
    while (Step < MaxSteps)
    {
        if (MapPos.y < 0.0 || MapPos.y >= GridResolution.y ||
            MapPos.x < LoadedMin.x || MapPos.x >= LoadedMax.x ||
            MapPos.z < LoadedMin.z || MapPos.z >= LoadedMax.z) break;

        float CurrentDist = dot(SideDist - DeltaDist, Mask) * VoxelSize;
        if (CurrentDist > COARSE_SWITCH_DISTANCE + COARSE_BLEND_BAND) break;

        vec3 BrickCoord = floor(MapPos / BrickSize);
        bool BrickChanged = any(notEqual(BrickCoord, LastBrickCoord));
        if (BrickChanged)
        {
            LastBrickOccupied = IsBrickOccupied(BrickCoord, InvBrickRes);
            LastBrickCoord = BrickCoord;
        }
        bool BrickOccupied = LastBrickOccupied;

        if (BrickOccupied)
        {
            float Dist = dot(SideDist - DeltaDist, Mask) * VoxelSize;
            float LodLevel = clamp(Dist * 0.02, 0.0, 3.0);

            vec3 Tc = GetVoxelTc(MapPos, InvGridRes);
            vec4 Vox = textureLod(VoxelGrid, Tc, LodLevel);

            if (Vox.a > 0.0 && IsChunkValid(MapPos))
            {
                bool IsHit = false;
                if (IgnoreOpacity > 0.0)
                {
                    if (abs(Vox.a - IgnoreOpacity) > 0.02) IsHit = true;
                }
                else
                {
                    IsHit = true;
                }

                if (IsHit)
                {
                    vec4 Mat = textureLod(MaterialGrid, Tc, LodLevel);
                    Result.Hit = true;
                    Result.Albedo = Vox.rgb;
                    Result.Normal = -StepDir * Mask;
                    Result.Roughness = clamp(Mat.r, 0.04, 1.0);
                    Result.Reflectivity = clamp(Mat.g, 0.0, 1.0);
                    Result.Refractivity = clamp(Mat.b, 0.0, 1.0);
                    Result.Opacity = Vox.a;
                    Result.HitPos = RayOrigin + RayDir * Dist;
                    Result.Dist = Dist;
                    return Result;
                }
            }
        }

        if (SideDist.x < SideDist.y)
        {
            if (SideDist.x < SideDist.z) { SideDist.x += DeltaDist.x; MapPos.x += StepDir.x; Mask = vec3(1.0, 0.0, 0.0); }
            else { SideDist.z += DeltaDist.z; MapPos.z += StepDir.z; Mask = vec3(0.0, 0.0, 1.0); }
        }
        else
        {
            if (SideDist.y < SideDist.z) { SideDist.y += DeltaDist.y; MapPos.y += StepDir.y; Mask = vec3(0.0, 1.0, 0.0); }
            else { SideDist.z += DeltaDist.z; MapPos.z += StepDir.z; Mask = vec3(0.0, 0.0, 1.0); }
        }
        Step++;
    }

    return Result;
}

float ComputeVoxelAo(vec3 HitPos, vec3 Normal)
{
    vec3 ScaledHitPos = HitPos / VoxelSize;
    vec3 MapPos = floor(ScaledHitPos + Normal * 0.5);
    vec3 OrthoU = (abs(Normal.y) < 0.9) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 OrthoV = cross(Normal, OrthoU);
    float TotalOcclusion = 0.0;
    const int Samples = 2;
    for (int I = 0; I < Samples; ++I)
    {
        float Angle = (float(I) / float(Samples)) * 6.283185;
        vec3 OffsetDir = normalize(Normal + OrthoU * cos(Angle) + OrthoV * sin(Angle));
        vec3 CheckPos = (MapPos + Normal) + OffsetDir * 1.2;
        vec3 CPos = floor(CheckPos);

        if (CPos.y >= 0.0 && CPos.y < GridResolution.y &&
            CPos.x >= LoadedMin.x && CPos.x < LoadedMax.x &&
            CPos.z >= LoadedMin.z && CPos.z < LoadedMax.z)
        {
            if (IsChunkValid(CPos) && texture(VoxelGrid, GetVoxelTc(CPos, InvGridResolution())).a > 0.0) TotalOcclusion += 0.25;
        }
    }
    return clamp(1.0 - TotalOcclusion, 0.15, 1.0);
}

vec3 FresnelSchlick(float CosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - CosTheta, 0.0, 1.0), 5.0);
}

vec3 FresnelSchlickRoughness(float CosTheta, vec3 F0, float Roughness)
{
    return F0 + (max(vec3(1.0 - Roughness), F0) - F0) * pow(clamp(1.0 - CosTheta, 0.0, 1.0), 5.0);
}

float DistributionGgx(vec3 N, vec3 H, float Roughness)
{
    float A = Roughness * Roughness;
    float A2 = A * A;
    float NoH = max(dot(N, H), 0.0);
    float NoH2 = NoH * NoH;
    float Nom = A2;
    float Denom = (NoH2 * (A2 - 1.0) + 1.0);
    return Nom / (3.1415926 * Denom * Denom);
}

float GeometrySchlickGgx(float NoV, float Roughness)
{
    float R = (Roughness + 1.0);
    float K = (R * R) / 8.0;
    return NoV / (NoV * (1.0 - K) + K);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float Roughness)
{
    return GeometrySchlickGgx(max(dot(N, V), 0.0), Roughness) * GeometrySchlickGgx(max(dot(N, L), 0.0), Roughness);
}

vec3 ShadePbr(HitResult Hit, vec3 V, vec3 L, float ShadowFactor, float AoFactor)
{
    vec3 N = Hit.Normal;
    vec3 H = normalize(V + L);
    float NoV = max(dot(N, V), 0.0);
    float NoL = max(dot(N, L), 0.0);

    vec3 F0 = mix(vec3(0.04), Hit.Albedo, Hit.Reflectivity);
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float Ndf = DistributionGgx(N, H, Hit.Roughness);
    float G = GeometrySmith(N, V, L, Hit.Roughness);
    vec3 Numerator = Ndf * G * F;
    float Denominator = 4.0 * NoV * NoL + 1e-4;
    vec3 Specular = Numerator / Denominator;

    vec3 Kd = (vec3(1.0) - F) * (1.0 - Hit.Reflectivity);
    vec3 Diffuse = Kd * Hit.Albedo / 3.1415926;
    vec3 DirectLighting = (Diffuse + Specular) * SunColor * NoL * ShadowFactor;

    vec3 Findirect = FresnelSchlickRoughness(NoV, F0, Hit.Roughness);
    vec3 KdIndirect = (vec3(1.0) - Findirect) * (1.0 - Hit.Reflectivity);
    vec3 AmbientSky = SkyColor(N, false) * Hit.Albedo * AoFactor * 0.6 * KdIndirect;
    vec3 MinimumAmbient = Hit.Albedo * 0.02;

    return DirectLighting + max(AmbientSky, MinimumAmbient);
}

float TraceShadow(vec3 Origin, vec3 Normal)
{
    if (max(dot(Normal, normalize(SunDirection)), 0.0) <= 0.0) return 1.0;

    vec3 Offset = Origin + Normal * (1e-3 * VoxelSize);

    HitResult ShadowHit = TraceVoxel(Offset, normalize(SunDirection), SHADOW_RAY_STEPS, 0.0);

    if (!ShadowHit.Hit) return 1.0;
    return (ShadowHit.Opacity < 0.95) ? 0.3 : 0.0;
}

vec3 ComputeReflection(HitResult Hit, vec3 V)
{
    vec3 ReflDir = reflect(-V, Hit.Normal);
    vec3 F0 = mix(vec3(0.04), Hit.Albedo, Hit.Reflectivity);
    vec3 F = FresnelSchlickRoughness(max(dot(Hit.Normal, V), 0.0), F0, Hit.Roughness);

    if (dot(F, vec3(0.3333)) < 0.005) return vec3(0.0);

    if (Hit.Roughness > 0.95)
    {
        return SkyColor(ReflDir, false) * F * 0.5;
    }

    HitResult R = TraceVoxel(Hit.HitPos + Hit.Normal * (1e-3 * VoxelSize), ReflDir, REFLECTION_DDA_STEPS, 0.0);

    vec3 HitColor;
    float TravelDist;

    if (!R.Hit)
    {
        HitColor = SkyColor(ReflDir, true);
        TravelDist = 100.0;
    }
    else
    {
        float Shadow = TraceShadow(R.HitPos, R.Normal);
        HitColor = ShadePbr(R, -ReflDir, normalize(SunDirection), Shadow, 1.0);
        TravelDist = R.Dist;
    }

    vec3 AmbientIrradiance = SkyColor(ReflDir, false) * 0.8;
    float ConeSpread = clamp(TravelDist * Hit.Roughness * 1.5, 0.0, 1.0);

    return mix(HitColor, AmbientIrradiance, ConeSpread) * F;
}

vec3 ApplyFog(vec3 FinalColor, float Dist, vec3 RayDir, vec3 CamPos)
{
    float FogDensity = 0.0015;
    float HeightFalloff = 0.05;
    float VolumetricFog = (FogDensity / HeightFalloff) * exp(-CamPos.y * HeightFalloff) * (1.0 - exp(-Dist * RayDir.y * HeightFalloff)) / (RayDir.y + 1e-5);
    float FogFactor = 1.0 - exp(-max(VolumetricFog, 0.0));
    vec3 ExtinctColor = SkyColor(RayDir, false);
    return mix(FinalColor, ExtinctColor, clamp(FogFactor, 0.0, 1.0));
}

vec3 ShadeHit(HitResult Hit, vec3 RayOrigin, vec3 RayDir)
{
    float ShadowFactor = TraceShadow(Hit.HitPos, Hit.Normal);
    float AoFactor = ComputeVoxelAo(Hit.HitPos, Hit.Normal);
    vec3 ViewDir = -RayDir;

    vec3 F0 = mix(vec3(0.04), Hit.Albedo, Hit.Reflectivity);
    vec3 Fresnel = FresnelSchlick(max(dot(ViewDir, Hit.Normal), 0.0), F0);

    vec3 DiffusePart = ShadePbr(Hit, ViewDir, normalize(SunDirection), ShadowFactor, AoFactor);
    vec3 ReflectionPart = (Hit.Reflectivity > 0.02) ? ComputeReflection(Hit, ViewDir) : vec3(0.0);

    vec3 SurfaceColor = mix(DiffusePart, ReflectionPart, Fresnel);

    float TransmitAmount = clamp(Hit.Refractivity + (1.0 - Hit.Opacity), 0.0, 1.0);
    if (TransmitAmount > 0.0)
    {
        float WaterIor = 1.333;
        bool Entering = dot(RayDir, Hit.Normal) < 0.0;
        vec3 Normal = Entering ? Hit.Normal : -Hit.Normal;
        float Eta = Entering ? (1.0 / WaterIor) : WaterIor;
        vec3 TransmitDir = refract(RayDir, Normal, Eta);

        if (dot(TransmitDir, TransmitDir) > 1e-4)
        {
            float MediumAlpha = Entering ? Hit.Opacity : 0.0;
            HitResult UnderHit = TraceVoxel(Hit.HitPos - Normal * (1e-3 * VoxelSize), normalize(TransmitDir), MAX_DDA_STEPS / 2, MediumAlpha);

            vec3 UnderColor = UnderHit.Hit ? ShadePbr(UnderHit, -normalize(TransmitDir), normalize(SunDirection), 1.0, 1.0) : SkyColor(normalize(TransmitDir), false);

            vec3 BaseTint = mix(vec3(1.0), Hit.Albedo, 0.8);
            vec3 Absorption = exp(-(vec3(1.0) - BaseTint) * 1.5 * (UnderHit.Hit ? UnderHit.Dist : 50.0));

            SurfaceColor = mix(SurfaceColor, UnderColor * Absorption, TransmitAmount * (1.0 - Fresnel.r));
        }
    }

    SurfaceColor = ApplyFog(SurfaceColor, Hit.Dist, RayDir, RayOrigin);
    return SurfaceColor;
}

vec4 effect(vec4 GlobalColor, Image Tex, vec2 TexCoord, vec2 ScreenCoord)
{
    vec2 Uv = (ScreenCoord - 0.5 * ScreenDimensions) / ScreenDimensions.y;
    Uv.y = -Uv.y;
    float Yaw = CameraRotation.x;
    float Pitch = CameraRotation.y;
    vec3 Forward = vec3(sin(Yaw) * cos(Pitch), sin(Pitch), -cos(Yaw) * cos(Pitch));
    vec3 Right = normalize(cross(Forward, vec3(0.0, 1.0, 0.0)));
    vec3 Up = cross(Right, Forward);
    vec3 RayOrigin = CameraPosition;
    vec3 RayDir = normalize(Forward + Right * Uv.x + Up * Uv.y);

    vec3 CamPosVoxel = floor(RayOrigin / VoxelSize);
    vec4 CamVox = texture(VoxelGrid, GetVoxelTc(CamPosVoxel, InvGridResolution()));
    float StartOpacity = 0.0;

    if (CamPosVoxel.x >= LoadedMin.x && CamPosVoxel.x < LoadedMax.x &&
        CamPosVoxel.z >= LoadedMin.z && CamPosVoxel.z < LoadedMax.z &&
        CamPosVoxel.y >= 0.0 && CamPosVoxel.y < GridResolution.y &&
        IsChunkValid(CamPosVoxel))
    {
        StartOpacity = (CamVox.a > 0.0 && CamVox.a < 0.98) ? CamVox.a : 0.0;
    }

    HitResult FineHit = TraceVoxel(RayOrigin, RayDir, MAX_DDA_STEPS, StartOpacity);

    float BlendStart = COARSE_SWITCH_DISTANCE - COARSE_BLEND_BAND;
    float BlendEnd = COARSE_SWITCH_DISTANCE + COARSE_BLEND_BAND;

    bool FineInBlendRange = FineHit.Hit && FineHit.Dist >= BlendStart;
    bool NeedCoarse = (!FineHit.Hit) || FineInBlendRange;

    vec3 FinalColor;

    if (!NeedCoarse)
    {
        
        FinalColor = ShadeHit(FineHit, RayOrigin, RayDir);
    }
    else
    {
        HitResult CoarseHit = TraceBrickCoarse(RayOrigin, RayDir, floor(RayOrigin / VoxelSize));

        vec3 FineColor;
        float FineDistForBlend;
        if (FineHit.Hit)
        {
            FineColor = ShadeHit(FineHit, RayOrigin, RayDir);
            FineDistForBlend = FineHit.Dist;
        }
        else
        {
            
            FineColor = ApplyFog(SkyColor(RayDir, true), 1000.0, RayDir, RayOrigin);
            FineDistForBlend = BlendEnd;
        }

        vec3 CoarseColor;
        if (CoarseHit.Hit)
        {
            CoarseColor = ShadeHit(CoarseHit, RayOrigin, RayDir);
        }
        else
        {
            CoarseColor = ApplyFog(SkyColor(RayDir, true), 1000.0, RayDir, RayOrigin);
        }

        float BlendT = smoothstep(BlendStart, BlendEnd, FineDistForBlend);
        FinalColor = mix(FineColor, CoarseColor, BlendT);
    }

    return vec4(FinalColor, 1.0);
}