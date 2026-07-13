local CoreFfi = require("ffi")

local FfiService = {}

CoreFfi.cdef[[
    typedef struct { uint8_t Cr, Cg, Cb, Al; } PackedVoxel;
    typedef struct { uint8_t Roughness, Reflectivity, Refractivity, Wtx; } PackedMaterial;
    typedef struct {
        uint8_t Lx, Ly_Lo, Ly_Hi, Lz;
        uint8_t Cr, Cg, Cb, Al;
        uint8_t Roughness, Reflectivity, Refractivity, Wtx;
    } VoxelEditRecord;
]]

local RecordBytes = CoreFfi.sizeof("VoxelEditRecord")

local DeltaBuilder = {}
DeltaBuilder.__index = DeltaBuilder

function FfiService.NewDeltaBuilder(MaxEdits)
    local Self = setmetatable({}, DeltaBuilder)
    Self.Buffer = love.data.newByteData(MaxEdits * RecordBytes)
    Self.Pointer = CoreFfi.cast("VoxelEditRecord*", Self.Buffer:getFFIPointer())
    Self.Count = 0
    Self.Max = MaxEdits
    return Self
end

function DeltaBuilder:Add(Lx, Ly, Lz, R, G, B, A, Rough, Refl, Refr, Wtx)
    if self.Count >= self.Max then return false end
    
    local Record = self.Pointer[self.Count]
    Record.Lx = Lx
    Record.Ly_Lo = Ly % 256
    Record.Ly_Hi = math.floor(Ly / 256)
    Record.Lz = Lz
    
    Record.Cr = R
    Record.Cg = G
    Record.Cb = B
    Record.Al = A
    
    Record.Roughness = Rough
    Record.Reflectivity = Refl
    Record.Refractivity = Refr
    Record.Wtx = Wtx
    
    self.Count = self.Count + 1
    return true
end

function DeltaBuilder:GetBuffer()
    if self.Count == self.Max then return self.Buffer end
    local Trimmed = love.data.newByteData(self.Count * RecordBytes)
    CoreFfi.copy(Trimmed:getFFIPointer(), self.Buffer:getFFIPointer(), self.Count * RecordBytes)
    return Trimmed
end

local ChunkEditor = {}
ChunkEditor.__index = ChunkEditor

function FfiService.NewChunkEditor(VoxelData, MaterialData, CX, CY, CZ)
    local Self = setmetatable({}, ChunkEditor)
    Self.VoxelPointer = CoreFfi.cast("PackedVoxel*", VoxelData:getFFIPointer())
    Self.MaterialPointer = CoreFfi.cast("PackedMaterial*", MaterialData:getFFIPointer())
    Self.CX = CX
    Self.CY = CY
    Self.CZ = CZ
    return Self
end

function ChunkEditor:GetIndex(X, Y, Z)
    return Y * (self.CX * self.CZ) + Z * self.CX + X
end

function ChunkEditor:SetVoxel(X, Y, Z, R, G, B, A)
    local Index = self:GetIndex(X, Y, Z)
    local Voxel = self.VoxelPointer[Index]
    Voxel.Cr = R
    Voxel.Cg = G
    Voxel.Cb = B
    Voxel.Al = A
end

function ChunkEditor:SetMaterial(X, Y, Z, Rough, Refl, Refr, Wtx)
    local Index = self:GetIndex(X, Y, Z)
    local Material = self.MaterialPointer[Index]
    Material.Roughness = Rough
    Material.Reflectivity = Refl
    Material.Refractivity = Refr
    Material.Wtx = Wtx
end

return FfiService