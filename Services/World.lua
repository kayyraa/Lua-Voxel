local Ffi = require("ffi")

Ffi.cdef[[
    typedef struct { uint8_t Cr, Cg, Cb, Al; } PackedVoxel;
    typedef struct { uint8_t Roughness, Reflectivity, Refractivity, Wtx; } PackedMaterial;
]]

local World = {}
World.__index = World

local CX, CY, CZ = 16, 256, 16
local ChunkBaseY = 64
local TotalVoxels = CX * CY * CZ

local Floor = math.floor
local Abs = math.abs
local Max = math.max
local Min = math.min
local Random = math.random

local Grad3 = {
    {1,1,0},{-1,1,0},{1,-1,0},{-1,-1,0},
    {1,0,1},{-1,0,1},{1,0,-1},{-1,0,-1},
    {0,1,1},{0,-1,1},{0,1,-1},{0,-1,-1}
}

local function BuildPermutation(Seed)
    local Perm = {}
    local State = Seed
    local function NextRandom()
        State = (State * 1103515245 + 12345) % 2147483648
        return State / 2147483648
    end
    for Index = 0, 255 do Perm[Index] = Index end
    for Index = 255, 1, -1 do
        local Swap = Floor(NextRandom() * (Index + 1))
        Perm[Index], Perm[Swap] = Perm[Swap], Perm[Index]
    end
    for Index = 0, 255 do Perm[256 + Index] = Perm[Index] end
    local PermMod12 = {}
    for Index = 0, 511 do PermMod12[Index] = Perm[Index] % 12 end
    return Perm, PermMod12
end

local PermA, PermModA12 = BuildPermutation(1337)
local PermB, PermModB12 = BuildPermutation(84719)
local PermC, PermModC12 = BuildPermutation(653219)
local PermD, PermModD12 = BuildPermutation(2182731)

local F2 = 0.3660254037844386
local G2 = 0.21132486540518713

local function Dot2(GradTable, Xi, Yi)
    return GradTable[1] * Xi + GradTable[2] * Yi
end

local function SimplexNoise2D(Perm, PermMod12, X, Y)
    local S = (X + Y) * F2
    local I = Floor(X + S)
    local J = Floor(Y + S)
    local T = (I + J) * G2
    local X0 = X - (I - T)
    local Y0 = Y - (J - T)

    local I1, J1
    if X0 > Y0 then I1, J1 = 1, 0 else I1, J1 = 0, 1 end

    local X1 = X0 - I1 + G2
    local Y1 = Y0 - J1 + G2
    local X2 = X0 - 1 + 2 * G2
    local Y2 = Y0 - 1 + 2 * G2

    local Ii = Floor(I) % 256
    local Jj = Floor(J) % 256
    if Ii < 0 then Ii = Ii + 256 end
    if Jj < 0 then Jj = Jj + 256 end

    local Gi0 = PermMod12[Perm[Ii + Perm[Jj]] % 256]
    local Gi1 = PermMod12[Perm[Ii + I1 + Perm[Jj + J1]] % 256]
    local Gi2 = PermMod12[Perm[Ii + 1 + Perm[Jj + 1]] % 256]

    local N0, N1, N2 = 0, 0, 0

    local T0 = 0.5 - X0 * X0 - Y0 * Y0
    if T0 >= 0 then
        T0 = T0 * T0
        N0 = T0 * T0 * Dot2(Grad3[Gi0 + 1], X0, Y0)
    end

    local T1 = 0.5 - X1 * X1 - Y1 * Y1
    if T1 >= 0 then
        T1 = T1 * T1
        N1 = T1 * T1 * Dot2(Grad3[Gi1 + 1], X1, Y1)
    end

    local T2 = 0.5 - X2 * X2 - Y2 * Y2
    if T2 >= 0 then
        T2 = T2 * T2
        N2 = T2 * T2 * Dot2(Grad3[Gi2 + 1], X2, Y2)
    end

    return 70 * (N0 + N1 + N2)
end

local function Fbm(Perm, PermMod12, X, Y, Octaves, Frequency, Lacunarity, Gain)
    local Amplitude = 1
    local Sum = 0
    local MaxAmp = 0
    local Freq = Frequency
    for _ = 1, Octaves do
        Sum = Sum + SimplexNoise2D(Perm, PermMod12, X * Freq, Y * Freq) * Amplitude
        MaxAmp = MaxAmp + Amplitude
        Amplitude = Amplitude * Gain
        Freq = Freq * Lacunarity
    end
    return Sum / MaxAmp
end

local function SmoothStep(EdgeA, EdgeB, X)
    local T = Max(0, Min(1, (X - EdgeA) / (EdgeB - EdgeA)))
    return T * T * (3 - 2 * T)
end

local function GetTerrainHeight(WorldX, WorldZ, SkipDetail)
    local Continent = Fbm(PermA, PermModA12, WorldX, WorldZ, 4, 0.0005, 2.0, 0.5)
    local Mountains = Fbm(PermB, PermModB12, WorldX, WorldZ, 6, 0.002, 2.0, 0.5)
    local Hills = Fbm(PermC, PermModC12, WorldX, WorldZ, 4, 0.008, 2.0, 0.5)

    local MountainMask = Fbm(PermD, PermModD12, WorldX, WorldZ, 2, 0.001, 2.0, 0.5)
    MountainMask = SmoothStep(0.15, 0.55, MountainMask)

    local Base = Continent * 40
    local Combined = Base + (Mountains * MountainMask * 120) + (Hills * 10 * (1 - MountainMask))

    return ChunkBaseY + Floor(Combined)
end

local function GetGrassColor(WorldX, WorldZ, Cheap)
    local BaseR, BaseG, BaseB = 50, 110, 40
    local Variation = math.random(-8, 8)
    return Max(0, Min(255, BaseR + Variation)), Max(0, Min(255, BaseG + Variation)), Max(0, Min(255, BaseB + Variation))
end

local SnowLineStart = 144
local SnowLineEnd = 160
local RockLineStart = 64
local RockLineEnd = 128

local function GetSurfaceColor(WorldX, WorldZ, Height)
    local GrassR, GrassG, GrassB = GetGrassColor(WorldX, WorldZ, false)
    local RockVariation = math.random(-10, 10)
    local RockR, RockG, RockB = Max(0, Min(255, 100 + RockVariation)), Max(0, Min(255, 96 + RockVariation)), Max(0, Min(255, 92 + RockVariation))
    local SnowVariation = math.random(-6, 6)
    local SnowR, SnowG, SnowB = Max(0, Min(255, 235 + SnowVariation)), Max(0, Min(255, 240 + SnowVariation)), Max(0, Min(255, 248 + SnowVariation))

    local RockBlend = SmoothStep(RockLineStart, RockLineEnd, Height)
    local ColorR = GrassR + (RockR - GrassR) * RockBlend
    local ColorG = GrassG + (RockG - GrassG) * RockBlend
    local ColorB = GrassB + (RockB - GrassB) * RockBlend

    local SnowBlend = SmoothStep(SnowLineStart, SnowLineEnd, Height)
    ColorR = ColorR + (SnowR - ColorR) * SnowBlend
    ColorG = ColorG + (SnowG - ColorG) * SnowBlend
    ColorB = ColorB + (SnowB - ColorB) * SnowBlend

    return Floor(ColorR), Floor(ColorG), Floor(ColorB)
end

local SharedVoxelBuffer = Ffi.new("PackedVoxel[?]", TotalVoxels)
local SharedMaterialBuffer = Ffi.new("PackedMaterial[?]", TotalVoxels)

local WaterLevel = ChunkBaseY + 8
local ShorelineSandRadius = 4

local function IsUnderwater(WorldX, WorldZ)
    return GetTerrainHeight(WorldX, WorldZ, false) < WaterLevel
end

local function ClampByte(Value)
    if Value < 0 then return 0 end
    if Value > 255 then return 255 end
    return Value
end

function World.GenerateChunkData(ChunkX, ChunkZ)
    Ffi.fill(SharedVoxelBuffer, TotalVoxels * 4, 0)
    Ffi.fill(SharedMaterialBuffer, TotalVoxels * 4, 0)
    local OriginX, OriginZ = ChunkX * CX, ChunkZ * CZ
    for LocalZ = 0, CZ - 1 do
        for LocalX = 0, CX - 1 do
            local WorldX, WorldZ = OriginX + LocalX, OriginZ + LocalZ
            local Height = GetTerrainHeight(WorldX, WorldZ, false)
            if Height >= CY then Height = CY - 1 end
            if Height < 0 then Height = 0 end
            local SurfaceR, SurfaceG, SurfaceB = GetSurfaceColor(WorldX, WorldZ, Height)
            local DirtR, DirtG, DirtB = 86, 61, 45
            local StoneR, StoneG, StoneB = 90, 90, 90
            local SandR, SandG, SandB = 194, 178, 128
            local IsSnowSurface = Height >= SnowLineStart

            local IsUnderwaterHere = Height < WaterLevel
            local IsNearShore = false
            if not IsUnderwaterHere then
                for Dz = -ShorelineSandRadius, ShorelineSandRadius do
                    for Dx = -ShorelineSandRadius, ShorelineSandRadius do
                        if IsUnderwater(WorldX + Dx, WorldZ + Dz) then
                            IsNearShore = true
                            break
                        end
                    end
                    if IsNearShore then break end
                end
            end
            local IsBeach = IsUnderwaterHere or IsNearShore

            local SandThickness = 6

            for LocalY = 0, Height do
                local Index = LocalY * (CX * CZ) + LocalZ * CX + LocalX
                if IsBeach and LocalY > Height - SandThickness then
                    SharedVoxelBuffer[Index].Cr = ClampByte(SandR + math.random(-4, 4))
                    SharedVoxelBuffer[Index].Cg = ClampByte(SandG + math.random(-4, 4))
                    SharedVoxelBuffer[Index].Cb = ClampByte(SandB + math.random(-4, 4))
                elseif LocalY == Height then
                    SharedVoxelBuffer[Index].Cr = ClampByte(SurfaceR + math.random(-4, 4))
                    SharedVoxelBuffer[Index].Cg = ClampByte(SurfaceG + math.random(-4, 4))
                    SharedVoxelBuffer[Index].Cb = ClampByte(SurfaceB + math.random(-4, 4))
                elseif LocalY > Height - 4 then
                    if IsSnowSurface then
                        SharedVoxelBuffer[Index].Cr = ClampByte(StoneR + math.random(-4, 4))
                        SharedVoxelBuffer[Index].Cg = ClampByte(StoneG + math.random(-4, 4))
                        SharedVoxelBuffer[Index].Cb = ClampByte(StoneB + math.random(-4, 4))
                    else
                        SharedVoxelBuffer[Index].Cr = ClampByte(DirtR + math.random(-4, 4))
                        SharedVoxelBuffer[Index].Cg = ClampByte(DirtG + math.random(-4, 4))
                        SharedVoxelBuffer[Index].Cb = ClampByte(DirtB + math.random(-4, 4))
                    end
                else
                    SharedVoxelBuffer[Index].Cr = ClampByte(StoneR + math.random(-4, 4))
                    SharedVoxelBuffer[Index].Cg = ClampByte(StoneG + math.random(-4, 4))
                    SharedVoxelBuffer[Index].Cb = ClampByte(StoneB + math.random(-4, 4))
                end
                SharedVoxelBuffer[Index].Al = 255
                SharedMaterialBuffer[Index].Roughness = 128
                SharedMaterialBuffer[Index].Reflectivity = 2
                SharedMaterialBuffer[Index].Refractivity = 0
            end

            if Height < WaterLevel then
                local FillTop = WaterLevel
                if FillTop >= CY then FillTop = CY - 1 end
                for LocalY = Height + 1, FillTop do
                    local Index = LocalY * (CX * CZ) + LocalZ * CX + LocalX
                    SharedVoxelBuffer[Index].Cr = ClampByte(100 + math.random(-2, 2))
                    SharedVoxelBuffer[Index].Cg = ClampByte(160 + math.random(-2, 2))
                    SharedVoxelBuffer[Index].Cb = ClampByte(220 + math.random(-2, 2))
                    SharedVoxelBuffer[Index].Al = 120

                    SharedMaterialBuffer[Index].Roughness = 2
                    SharedMaterialBuffer[Index].Reflectivity = 255
                    SharedMaterialBuffer[Index].Refractivity = 128
                    SharedMaterialBuffer[Index].Wtx = 1
                end
            end
        end
    end
    return SharedVoxelBuffer, SharedMaterialBuffer
end

return World