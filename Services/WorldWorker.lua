-- Services/WorldWorker.lua
local JobChannelName, ResultChannelName = ...

local Ffi = require("ffi")
local World = require("Services.World")
local RegionStore = require("Services.RegionStore")
local ChunkUpdate = require("Services.ChunkUpdate")

Ffi.cdef[[
    typedef struct { uint8_t Cr, Cg, Cb, Al; } PackedVoxel;
    typedef struct { uint8_t Roughness, Reflectivity, Refractivity, Wtx; } PackedMaterial;
    typedef struct {
        uint8_t Lx, Ly_Lo, Ly_Hi, Lz;
        uint8_t Cr, Cg, Cb, Al;
        uint8_t Roughness, Reflectivity, Refractivity, Wtx;
    } VoxelEditRecord;
]]

local JobChannel = love.thread.getChannel(JobChannelName)
local ResultChannel = love.thread.getChannel(ResultChannelName)

local Store = RegionStore.New("Regions")

local CX, CY, CZ = 16, 256, 16
local ChunkVoxelCount = CX * CY * CZ
local ChunkByteLength = ChunkVoxelCount * 4
local RecordBytes = Ffi.sizeof("VoxelEditRecord")

local function VoxelIndex(Lx, Ly, Lz)
    return Ly * (CX * CZ) + Lz * CX + Lx
end

local function ApplyDelta(DeltaBuffer, VoxelBuffer, MaterialBuffer)
    local Count = DeltaBuffer:getSize() / RecordBytes
    local Ptr = Ffi.cast("VoxelEditRecord*", DeltaBuffer:getFFIPointer())

    for Index = 0, Count - 1 do
        local Record = Ptr[Index]
        local Ly = Record.Ly_Lo + Record.Ly_Hi * 256
        local VoxelIdx = VoxelIndex(Record.Lx, Ly, Record.Lz)

        VoxelBuffer[VoxelIdx].Cr = Record.Cr
        VoxelBuffer[VoxelIdx].Cg = Record.Cg
        VoxelBuffer[VoxelIdx].Cb = Record.Cb
        VoxelBuffer[VoxelIdx].Al = Record.Al

        MaterialBuffer[VoxelIdx].Roughness = Record.Roughness
        MaterialBuffer[VoxelIdx].Reflectivity = Record.Reflectivity
        MaterialBuffer[VoxelIdx].Refractivity = Record.Refractivity
        MaterialBuffer[VoxelIdx].Wtx = Record.Wtx
    end
end

local function EncodeChunk(Cx, Cz, VoxelPointer, MaterialPointer)
    ResultChannel:push({
        Kind = "chunk",
        Cx = Cx,
        Cz = Cz,
        VoxelData = love.data.newByteData(Ffi.string(VoxelPointer, ChunkByteLength)),
        MaterialData = love.data.newByteData(Ffi.string(MaterialPointer, ChunkByteLength))
    })
end

while true do
    local Job = JobChannel:demand()
    if Job == "quit" then break end

    if type(Job) == "string" then
        local Kind, CxStr, CzStr = Job:match("(%a+),(-?%d+),(-?%d+)")
        local Cx, Cz = tonumber(CxStr), tonumber(CzStr)

        if Kind == "chunk" then
            local VB, MB = World.GenerateChunkData(Cx, Cz)

            local DeltaBuffer = Store:LoadDelta(Cx, Cz)
            if DeltaBuffer then ApplyDelta(DeltaBuffer, VB, MB) end

            EncodeChunk(Cx, Cz, VB, MB)
        end
    elseif type(Job) == "table" and Job.Kind == "save" then
        Store:SaveDelta(Job.Cx, Job.Cz, Job.DeltaBuffer)
        ResultChannel:push({ Kind = "saveComplete", Cx = Job.Cx, Cz = Job.Cz })
    end
end