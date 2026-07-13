local Ffi = require("ffi")

local ChunkWorkerPool = {}
ChunkWorkerPool.__index = ChunkWorkerPool

local PoolInstanceCounter = 0

local function GetWorkerCount()
    local Count = love.system.getProcessorCount and love.system.getProcessorCount() or 4
    if Count < 2 then Count = 2 end
    if Count > 8 then Count = 8 end
    return Count - 1
end

function ChunkWorkerPool.New(WorkerScriptPath)
    local Self = setmetatable({}, ChunkWorkerPool)
    PoolInstanceCounter = PoolInstanceCounter + 1
    local InstanceId = PoolInstanceCounter
    Self.JobChannelName = "ChunkJobs_" .. InstanceId
    Self.ResultChannelName = "ChunkResults_" .. InstanceId
    Self.JobChannel = love.thread.getChannel(Self.JobChannelName)
    Self.ResultChannel = love.thread.getChannel(Self.ResultChannelName)
    Self.Threads = {}
    Self.WorkerCount = GetWorkerCount()
    Self.InFlightJobs = {}
    Self.InFlightCount = 0
    Self.MaxInFlight = Self.WorkerCount * 3
    for _ = 1, Self.WorkerCount do
        local Thread = love.thread.newThread(WorkerScriptPath)
        Thread:start(Self.JobChannelName, Self.ResultChannelName)
        Self.Threads[#Self.Threads + 1] = Thread
    end
    return Self
end

function ChunkWorkerPool:CanSubmit()
    return self.InFlightCount < self.MaxInFlight
end

function ChunkWorkerPool:SubmitChunkJob(ChunkX, ChunkZ)
    local Key = ChunkX .. "," .. ChunkZ
    if self.InFlightJobs[Key] then return false end
    self.JobChannel:push("chunk," .. ChunkX .. "," .. ChunkZ)
    self.InFlightJobs[Key] = true
    self.InFlightCount = self.InFlightCount + 1
    return true
end

function ChunkWorkerPool:SubmitSaveJob(ChunkX, ChunkZ, DeltaBuffer)
    self.JobChannel:push({
        Kind = "save",
        Cx = ChunkX,
        Cz = ChunkZ,
        DeltaBuffer = DeltaBuffer
    })
    return true
end

function ChunkWorkerPool:PollResults(MaxResults)
    local Results = {}
    local Count = 0
    while Count < MaxResults do
        local Result = self.ResultChannel:pop()
        if not Result then break end

        if Result.Kind == "chunk" then
            Results[Count + 1] = {
                Kind = Result.Kind,
                ChunkX = Result.Cx,
                ChunkZ = Result.Cz,
                FromDisk = Result.FromDisk,
                VoxelData = Result.VoxelData,
                MaterialData = Result.MaterialData
            }
            local Key = Result.Cx .. "," .. Result.Cz
            if self.InFlightJobs[Key] then
                self.InFlightJobs[Key] = nil
                self.InFlightCount = self.InFlightCount - 1
            end
        elseif Result.Kind == "saveComplete" then
            Results[Count + 1] = {
                Kind = Result.Kind,
                ChunkX = Result.Cx,
                ChunkZ = Result.Cz
            }
        end
        Count = Count + 1
    end
    return Results
end

function ChunkWorkerPool:Shutdown()
    for _ = 1, self.WorkerCount do self.JobChannel:push("quit") end
    for _, Thread in ipairs(self.Threads) do Thread:wait() end
end

return ChunkWorkerPool
