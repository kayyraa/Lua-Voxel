local Ffi = require("ffi")

Ffi.cdef[[
    typedef struct {
        uint8_t Lx, Ly_Lo, Ly_Hi, Lz;
        uint8_t Cr, Cg, Cb, Al;
        uint8_t Roughness, Reflectivity, Refractivity, Wtx;
    } VoxelEditRecord;
]]

local DirtyTracker = {}

local EditLists = {}
local RecordBytes = Ffi.sizeof("VoxelEditRecord")

local function Key(Cx, Cz)
    return Cx .. "," .. Cz
end

function DirtyTracker.RecordEdit(Cx, Cz, LocalX, LocalY, LocalZ, Cr, Cg, Cb, Al, Roughness, Reflectivity, Refractivity)
    local K = Key(Cx, Cz)
    local List = EditLists[K]
    if not List then
        List = {}
        EditLists[K] = List
    end

    List[#List + 1] = {
        Lx = LocalX,
        Ly = LocalY,
        Lz = LocalZ,
        Cr = Cr, Cg = Cg, Cb = Cb, Al = Al,
        Roughness = Roughness, Reflectivity = Reflectivity, Refractivity = Refractivity
    }
end

function DirtyTracker.IsDirty(Cx, Cz)
    local List = EditLists[Key(Cx, Cz)]
    return List ~= nil and #List > 0
end

function DirtyTracker.GetEditCount(Cx, Cz)
    local List = EditLists[Key(Cx, Cz)]
    return List and #List or 0
end

function DirtyTracker.EncodeDeltaBuffer(Cx, Cz)
    local List = EditLists[Key(Cx, Cz)]
    if not List or #List == 0 then return nil end

    local Count = #List
    local Buffer = love.data.newByteData(Count * RecordBytes)
    local Ptr = Ffi.cast("VoxelEditRecord*", Buffer:getFFIPointer())

    for Index = 1, Count do
        local Edit = List[Index]
        local Record = Ptr[Index - 1]
        Record.Lx = Edit.Lx
        Record.Ly_Lo = Edit.Ly % 256
        Record.Ly_Hi = math.floor(Edit.Ly / 256)
        Record.Lz = Edit.Lz
        Record.Cr = Edit.Cr
        Record.Cg = Edit.Cg
        Record.Cb = Edit.Cb
        Record.Al = Edit.Al
        Record.Roughness = Edit.Roughness
        Record.Reflectivity = Edit.Reflectivity
        Record.Refractivity = Edit.Refractivity
        Record.Padding = 0
    end

    return Buffer
end

function DirtyTracker.ClearDirty(Cx, Cz)
    EditLists[Key(Cx, Cz)] = nil
end

DirtyTracker.RecordBytes = RecordBytes

return DirtyTracker
