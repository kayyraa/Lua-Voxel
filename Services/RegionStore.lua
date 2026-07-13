local Ffi = require("ffi")

local RegionStore = {}
RegionStore.__index = RegionStore

local RegionSpan = 16
local SlotsPerRegion = RegionSpan * RegionSpan
local HeaderEntryBytes = 12
local HeaderBytes = SlotsPerRegion * HeaderEntryBytes

local function FloorDiv(Value, Divisor)
    return math.floor(Value / Divisor)
end

local function Mod(Value, Divisor)
    local Result = Value % Divisor
    if Result < 0 then Result = Result + Divisor end
    return Result
end

local function RegionCoords(Cx, Cz)
    return FloorDiv(Cx, RegionSpan), FloorDiv(Cz, RegionSpan)
end

local function SlotIndex(Cx, Cz)
    local Lx, Lz = Mod(Cx, RegionSpan), Mod(Cz, RegionSpan)
    return Lz * RegionSpan + Lx
end

function RegionStore.New(Directory)
    local Self = setmetatable({}, RegionStore)
    Self.Directory = Directory or "Regions"
    love.filesystem.createDirectory(Self.Directory)
    return Self
end

function RegionStore:RegionPath(Rx, Rz)
    return self.Directory .. "/Region_" .. Rx .. "_" .. Rz .. ".dat"
end

local function ReadHeader(FileData)
    local Header = {}
    if not FileData or FileData:getSize() < HeaderBytes then
        for Index = 0, SlotsPerRegion - 1 do Header[Index] = { Offset = 0, Length = 0, Capacity = 0 } end
        return Header
    end
    local Ptr = Ffi.cast("uint32_t*", FileData:getFFIPointer())
    for Index = 0, SlotsPerRegion - 1 do
        Header[Index] = {
            Offset = Ptr[Index * 3],
            Length = Ptr[Index * 3 + 1],
            Capacity = Ptr[Index * 3 + 2]
        }
    end
    return Header
end

local function SerializeHeader(Header)
    local Buffer = love.data.newByteData(HeaderBytes)
    local Ptr = Ffi.cast("uint32_t*", Buffer:getFFIPointer())
    for Index = 0, SlotsPerRegion - 1 do
        local Entry = Header[Index]
        Ptr[Index * 3] = Entry.Offset
        Ptr[Index * 3 + 1] = Entry.Length
        Ptr[Index * 3 + 2] = Entry.Capacity or Entry.Length
    end
    return Buffer
end

function RegionStore:SaveDelta(Cx, Cz, DeltaBuffer)
    local Rx, Rz = RegionCoords(Cx, Cz)
    local Path = self:RegionPath(Rx, Rz)
    local Slot = SlotIndex(Cx, Cz)

    local ExistingRaw = love.filesystem.getInfo(Path) and love.filesystem.read("data", Path) or nil
    local Header = ReadHeader(ExistingRaw)

    local PayloadSize = DeltaBuffer:getSize()

    local FileBody
    if ExistingRaw then
        FileBody = love.data.newByteData(ExistingRaw:getSize())
        Ffi.copy(FileBody:getFFIPointer(), ExistingRaw:getFFIPointer(), ExistingRaw:getSize())
    else
        FileBody = love.data.newByteData(HeaderBytes)
    end

    local ExistingEntry = Header[Slot]
    local WriteOffset
    local NeedsAppend = true

    if ExistingEntry.Capacity >= PayloadSize and ExistingEntry.Offset >= HeaderBytes then
        WriteOffset = ExistingEntry.Offset
        NeedsAppend = false
    else
        WriteOffset = FileBody:getSize()
    end

    local NewSize = NeedsAppend and (WriteOffset + PayloadSize) or FileBody:getSize()
    local NewBody = love.data.newByteData(math.max(NewSize, FileBody:getSize()))
    Ffi.copy(NewBody:getFFIPointer(), FileBody:getFFIPointer(), FileBody:getSize())

    local DestPtr = Ffi.cast("uint8_t*", NewBody:getFFIPointer()) + WriteOffset
    Ffi.copy(DestPtr, DeltaBuffer:getFFIPointer(), PayloadSize)

    local Capacity = NeedsAppend and PayloadSize or math.max(ExistingEntry.Capacity, PayloadSize)
    Header[Slot] = { Offset = WriteOffset, Length = PayloadSize, Capacity = Capacity }
    local HeaderBuffer = SerializeHeader(Header)
    Ffi.copy(NewBody:getFFIPointer(), HeaderBuffer:getFFIPointer(), HeaderBytes)

    love.filesystem.write(Path, NewBody)
end

function RegionStore:LoadDelta(Cx, Cz)
    local Rx, Rz = RegionCoords(Cx, Cz)
    local Path = self:RegionPath(Rx, Rz)
    if not love.filesystem.getInfo(Path) then return nil end

    local FileData = love.filesystem.read("data", Path)
    if not FileData then return nil end

    local Slot = SlotIndex(Cx, Cz)
    local Header = ReadHeader(FileData)
    local Entry = Header[Slot]
    if Entry.Length == 0 then return nil end

    local DeltaBuffer = love.data.newByteData(Entry.Length)
    local SrcPtr = Ffi.cast("uint8_t*", FileData:getFFIPointer()) + Entry.Offset
    Ffi.copy(DeltaBuffer:getFFIPointer(), SrcPtr, Entry.Length)

    return DeltaBuffer
end

function RegionStore:Has(Cx, Cz)
    local Rx, Rz = RegionCoords(Cx, Cz)
    local Path = self:RegionPath(Rx, Rz)
    if not love.filesystem.getInfo(Path) then return false end
    local FileData = love.filesystem.read("data", Path)
    if not FileData then return false end
    local Header = ReadHeader(FileData)
    local Entry = Header[SlotIndex(Cx, Cz)]
    return Entry.Length > 0
end

return RegionStore
