local Bit = require("bit")

local ChunkStreamer = {}
ChunkStreamer.__index = ChunkStreamer

local ChunkStateUnloaded = 0
local ChunkStateQueued = 1
local ChunkStateGenerating = 2
local ChunkStateUploading = 3
local ChunkStateLoaded = 4

ChunkStreamer.StateUnloaded = ChunkStateUnloaded
ChunkStreamer.StateQueued = ChunkStateQueued
ChunkStreamer.StateGenerating = ChunkStateGenerating
ChunkStreamer.StateUploading = ChunkStateUploading
ChunkStreamer.StateLoaded = ChunkStateLoaded

local function SpreadBits16(X)
    X = Bit.band(X, 0xFFFF)
    X = Bit.band(Bit.bor(X, Bit.lshift(X, 8)), 0x00FF00FF)
    X = Bit.band(Bit.bor(X, Bit.lshift(X, 4)), 0x0F0F0F0F)
    X = Bit.band(Bit.bor(X, Bit.lshift(X, 2)), 0x33333333)
    X = Bit.band(Bit.bor(X, Bit.lshift(X, 1)), 0x55555555)
    return X
end

local function ChunkKey(Cx, Cz)
    local Ux = Bit.band(Cx + 32768, 0xFFFF)
    local Uz = Bit.band(Cz + 32768, 0xFFFF)
    return Bit.bor(SpreadBits16(Ux), Bit.lshift(SpreadBits16(Uz), 1))
end

function ChunkStreamer.New(Config)
    local Self = setmetatable({}, ChunkStreamer)
    Self.Radius = Config.Radius
    Self.SafeZoneFraction = Config.SafeZoneFraction or 0.5
    Self.NeighborPadding = Config.NeighborPadding or 0
    Self.OnChunkNeeded = Config.OnChunkNeeded
    Self.OnChunkEvicted = Config.OnChunkEvicted
    Self.MaxSubmitsPerFrame = Config.MaxSubmitsPerFrame or 8

    Self.AnchorX, Self.AnchorZ = 0, 0
    Self.Initialized = false

    Self.ChunkStates = {}
    Self.PendingQueue = {}
    Self.PendingQueueDirty = false

    return Self
end

local function SortByDistanceToAnchor(A, B, AnchorX, AnchorZ)
    local Ax, Az = A[1] - AnchorX, A[2] - AnchorZ
    local Bx, Bz = B[1] - AnchorX, B[2] - AnchorZ
    return (Ax * Ax + Az * Az) < (Bx * Bx + Bz * Bz)
end

function ChunkStreamer:RebuildQueueOrder()
    if #self.PendingQueue <= 1 then return end
    local AnchorX, AnchorZ = self.AnchorX, self.AnchorZ
    table.sort(self.PendingQueue, function(A, B)
        return SortByDistanceToAnchor(A, B, AnchorX, AnchorZ)
    end)
end

function ChunkStreamer:Reanchor(NewAnchorX, NewAnchorZ)
    local Radius = self.Radius
    local EffectiveRadius = Radius + self.NeighborPadding

    for Key, Entry in pairs(self.ChunkStates) do
        local Cx, Cz = Entry.X, Entry.Z
        if math.abs(Cx - NewAnchorX) > EffectiveRadius or math.abs(Cz - NewAnchorZ) > EffectiveRadius then
            self.ChunkStates[Key] = nil
            if self.OnChunkEvicted then self.OnChunkEvicted(Cx, Cz) end
        end
    end

    for Dz = -EffectiveRadius, EffectiveRadius do
        for Dx = -EffectiveRadius, EffectiveRadius do
            local Cx, Cz = NewAnchorX + Dx, NewAnchorZ + Dz
            local Key = ChunkKey(Cx, Cz)
            if not self.ChunkStates[Key] then
                self.ChunkStates[Key] = { X = Cx, Z = Cz, State = ChunkStateQueued }
                self.PendingQueue[#self.PendingQueue + 1] = { Cx, Cz }
            end
        end
    end

    self.AnchorX, self.AnchorZ = NewAnchorX, NewAnchorZ
    self.PendingQueueDirty = true
end

function ChunkStreamer:Update(CamChunkX, CamChunkZ)
    if not self.Initialized then
        self.Initialized = true
        self:Reanchor(CamChunkX, CamChunkZ)
        return true
    end

    local SafeRadius = self.Radius * self.SafeZoneFraction
    if math.abs(CamChunkX - self.AnchorX) > SafeRadius or math.abs(CamChunkZ - self.AnchorZ) > SafeRadius then
        self:Reanchor(CamChunkX, CamChunkZ)
        return true
    end

    return false
end

function ChunkStreamer:PumpQueue(SubmitFn)
    if self.PendingQueueDirty then
        self:RebuildQueueOrder()
        self.PendingQueueDirty = false
    end

    local Submitted = 0
    local WriteIndex = 1
    local QueueLength = #self.PendingQueue

    for ReadIndex = 1, QueueLength do
        local Entry = self.PendingQueue[ReadIndex]
        local Cx, Cz = Entry[1], Entry[2]
        local Key = ChunkKey(Cx, Cz)
        local StateEntry = self.ChunkStates[Key]

        if StateEntry and StateEntry.State == ChunkStateQueued and Submitted < self.MaxSubmitsPerFrame then
            if SubmitFn(Cx, Cz) then
                StateEntry.State = ChunkStateGenerating
                Submitted = Submitted + 1
            else
                self.PendingQueue[WriteIndex] = Entry
                WriteIndex = WriteIndex + 1
            end
        elseif StateEntry and StateEntry.State == ChunkStateQueued then
            self.PendingQueue[WriteIndex] = Entry
            WriteIndex = WriteIndex + 1
        end
    end

    for Index = QueueLength, WriteIndex, -1 do
        self.PendingQueue[Index] = nil
    end
end

function ChunkStreamer:MarkLoaded(Cx, Cz)
    local Key = ChunkKey(Cx, Cz)
    local Entry = self.ChunkStates[Key]
    if Entry then Entry.State = ChunkStateLoaded end
end

function ChunkStreamer:MarkUnloadedIfStale(Cx, Cz)
    local Key = ChunkKey(Cx, Cz)
    local Entry = self.ChunkStates[Key]
    local EffectiveRadius = self.Radius + self.NeighborPadding
    if not Entry or math.abs(Cx - self.AnchorX) > EffectiveRadius or math.abs(Cz - self.AnchorZ) > EffectiveRadius then
        return false
    end
    return true
end

function ChunkStreamer:GetState(Cx, Cz)
    local Entry = self.ChunkStates[ChunkKey(Cx, Cz)]
    return Entry and Entry.State or ChunkStateUnloaded
end

function ChunkStreamer:GetBounds()
    local Radius = self.Radius
    return self.AnchorX - Radius, self.AnchorZ - Radius, self.AnchorX + Radius, self.AnchorZ + Radius
end

ChunkStreamer.ChunkKey = ChunkKey

return ChunkStreamer