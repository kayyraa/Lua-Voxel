local Fabric = require("Services.Fabric")
local Shader = require("Services.Shader")
local Color = require("Services.Color")
local Gui = require("Services.Gui")
local ChunkStreamer = require("Services.ChunkStreamer")
local ChunkWorkerPool = require("Services.ChunkWorkerPool")
local DirtyTracker = require("Services.DirtyTracker")
local Ffi = require("ffi")
local FfiService = require("Services.Ffi")

local _, _, Flags = love.window.getMode()
local BackgroundColor = Color.FromRGBA(0, 0, 0)
local TextColor = Color.FromRGBA(255, 255, 255)

local VoxelSize = 0.25
local Camera = { CFrame = { Position = {0, 48, 0}, Rotation = {0, 0, 0} }, TargetCFrame = { Position = {0, 48, 0}, Rotation = {0, 0, 0} } }
local Keys = {}
local PathTracerShader

local ChunkRadius = 48
local ChunkNeighborPadding = 1

local TextureChunkSpan = 2 * (ChunkRadius + ChunkNeighborPadding) + 4
local GridResolutionX = TextureChunkSpan * 16
local GridResolutionY = 256
local GridResolutionZ = TextureChunkSpan * 16

local VoxelTexture3D, MaterialTexture3D

local BrickSize = 8
local BrickResolutionX = GridResolutionX / BrickSize
local BrickResolutionY = GridResolutionY / BrickSize
local BrickResolutionZ = GridResolutionZ / BrickSize
local BrickTexture3D
local BrickImageDatas

local ChunkBaseY = 64

local SunDirection = { 0.4, 0.8, -0.3 }
local SunColor = { 1.0, 0.92, 0.78 }

local RenderCanvas

local ChunkUploadBudgetSeconds = 0.004
local MaxResultsPerPoll = 32

local VoxelStreamer
local VoxelWorkerPool

local PendingChunkUploads = {}
local PendingChunkUploadCount = 0

local ScratchVoxelImage
local ScratchMaterialImage
local ScratchVoxelPointer
local ScratchMaterialPointer
local ScratchVoxelBytePointer

local ChunkStateImageData
local ChunkStateImage

local BrickColumnsPerChunk = GridResolutionY / BrickSize
local BrickOccupancyScratch = {}
for Index = 1, 2 * BrickColumnsPerChunk * 2 do BrickOccupancyScratch[Index] = 0 end

local function NewHdrCanvas(Width, Height) return love.graphics.newCanvas(Width, Height, { format = "rgba16f" }) end
local function RebuildCanvases(Width, Height) RenderCanvas = NewHdrCanvas(Width, Height) end
local function GetCameraChunk() return math.floor((Camera.CFrame.Position[1] / VoxelSize) / 16), math.floor((Camera.CFrame.Position[3] / VoxelSize) / 16) end

function love.load()
    love.graphics.setFont(love.graphics.newFont("Font.ttf", 16))
    love.window.setMode(1280, 768, { resizable = true, vsync = 0 })
    love.mouse.setRelativeMode(true)
    love.mouse.setVisible(false)
    PathTracerShader = Shader.New()
    local W, H = love.graphics.getDimensions()
    RebuildCanvases(W, H)

    local VB1, VB2 = {}, {}
    for I = 1, GridResolutionZ do
        VB1[I] = love.image.newImageData(GridResolutionX, GridResolutionY)
        VB2[I] = love.image.newImageData(GridResolutionX, GridResolutionY)
    end
    VoxelTexture3D = love.graphics.newVolumeImage(VB1, {mipmaps = false, linear = false})
    MaterialTexture3D = love.graphics.newVolumeImage(VB2, {mipmaps = false, linear = false})
    VoxelTexture3D:setFilter("nearest", "nearest"); VoxelTexture3D:setWrap("repeat", "repeat", "repeat")
    MaterialTexture3D:setFilter("nearest", "nearest"); MaterialTexture3D:setWrap("repeat", "repeat", "repeat")

    local Brick = {}
    for I = 1, BrickResolutionZ do Brick[I] = love.image.newImageData(BrickResolutionX, BrickResolutionY, "r8") end
    BrickTexture3D = love.graphics.newVolumeImage(Brick, {mipmaps = false, linear = false})
    BrickTexture3D:setFilter("nearest", "nearest")
    BrickTexture3D:setWrap("repeat", "repeat", "repeat")
    BrickImageDatas = Brick

    ScratchVoxelImage = love.image.newImageData(16, GridResolutionY)
    ScratchMaterialImage = love.image.newImageData(16, GridResolutionY)
    ScratchVoxelPointer = Ffi.cast("uint32_t*", ScratchVoxelImage:getFFIPointer())
    ScratchMaterialPointer = Ffi.cast("uint32_t*", ScratchMaterialImage:getFFIPointer())
    ScratchVoxelBytePointer = Ffi.cast("uint8_t*", ScratchVoxelImage:getFFIPointer())

    ChunkStateImageData = love.image.newImageData(TextureChunkSpan, TextureChunkSpan, "rgba32f")
    do
        local Ptr = Ffi.cast("float*", ChunkStateImageData:getFFIPointer())
        for I = 0, TextureChunkSpan * TextureChunkSpan * 4 - 1 do Ptr[I] = -999999.0 end
    end
    ChunkStateImage = love.graphics.newImage(ChunkStateImageData)
    ChunkStateImage:setFilter("nearest", "nearest")

    VoxelWorkerPool = ChunkWorkerPool.New("Services/WorldWorker.lua")

    VoxelStreamer = ChunkStreamer.New({
        Radius = ChunkRadius,
        SafeZoneFraction = 0.5,
        NeighborPadding = ChunkNeighborPadding,
        MaxSubmitsPerFrame = 16,
        OnChunkEvicted = function(Cx, Cz)
            if DirtyTracker.IsDirty(Cx, Cz) then
                local DeltaBuffer = DirtyTracker.EncodeDeltaBuffer(Cx, Cz)
                if DeltaBuffer then
                    VoxelWorkerPool:SubmitSaveJob(Cx, Cz, DeltaBuffer)
                end
                DirtyTracker.ClearDirty(Cx, Cz)
            end
        end,
    })

    local Builder = FfiService.NewDeltaBuilder(9)
    for Dz = 0, 2 do
        for Dx = 0, 2 do
            Builder:Add(Dx, 24, Dz, 100, 160, 220, 120, 2, 255, 128, 1)
        end
    end
    VoxelWorkerPool:SubmitSaveJob(0, 0, Builder:GetBuffer())
end

local function UploadChunkToTexture(Cx, Cz, VoxelData, MaterialData)
    local VP, MP = Ffi.cast("uint32_t*", VoxelData:getFFIPointer()), Ffi.cast("uint32_t*", MaterialData:getFFIPointer())
    local MX, MZ = (Cx * 16) % GridResolutionX, (Cz * 16) % GridResolutionZ

    for Index = 1, 2 * BrickColumnsPerChunk * 2 do BrickOccupancyScratch[Index] = 0 end

    for Pz = 0, 15 do
        for Py = 0, GridResolutionY - 1 do
            Ffi.copy(ScratchVoxelPointer + Py * 16, VP + Py * 256 + Pz * 16, 64)
            Ffi.copy(ScratchMaterialPointer + Py * 16, MP + Py * 256 + Pz * 16, 64)
        end
        VoxelTexture3D:replacePixels(ScratchVoxelImage, (MZ + Pz) % GridResolutionZ + 1, 1, MX, 0)
        MaterialTexture3D:replacePixels(ScratchMaterialImage, (MZ + Pz) % GridResolutionZ + 1, 1, MX, 0)

        local BrickLocalZ = math.floor(Pz / BrickSize)
        for Py = 0, GridResolutionY - 1 do
            local BrickY = math.floor(Py / BrickSize)
            for Px = 0, 15 do
                local Alpha = ScratchVoxelBytePointer[(Py * 16 + Px) * 4 + 3]
                if Alpha > 0 then
                    local BrickLocalX = math.floor(Px / BrickSize)
                    local Idx = BrickLocalZ * (2 * BrickColumnsPerChunk) + BrickY * 2 + BrickLocalX + 1
                    BrickOccupancyScratch[Idx] = 255
                end
            end
        end
    end

    local BrickMX, BrickMZ = (Cx * 2) % BrickResolutionX, (Cz * 2) % BrickResolutionZ
    for BrickLocalZ = 0, 1 do
        local Slice = (BrickMZ + BrickLocalZ) % BrickResolutionZ + 1
        local ImgData = BrickImageDatas[Slice]
        local Ptr = Ffi.cast("uint8_t*", ImgData:getFFIPointer())
        for BrickY = 0, BrickColumnsPerChunk - 1 do
            for BrickLocalX = 0, 1 do
                local Idx = BrickLocalZ * (2 * BrickColumnsPerChunk) + BrickY * 2 + BrickLocalX + 1
                local WriteX = (BrickMX + BrickLocalX) % BrickResolutionX
                Ptr[BrickY * BrickResolutionX + WriteX] = BrickOccupancyScratch[Idx]
            end
        end
        BrickTexture3D:replacePixels(ImgData, Slice, 1, 0, 0)
    end

    local StateX, StateZ = Cx % TextureChunkSpan, Cz % TextureChunkSpan
    local Ptr = Ffi.cast("float*", ChunkStateImageData:getFFIPointer())
    local Index = (StateZ * TextureChunkSpan + StateX) * 4
    Ptr[Index] = Cx
    Ptr[Index + 1] = Cz
    Ptr[Index + 2] = 1.0
    Ptr[Index + 3] = 1.0
end

local function PumpVoxelStreaming()
    VoxelStreamer:PumpQueue(function(Cx, Cz)
        if not VoxelWorkerPool:CanSubmit() then return false end
        return VoxelWorkerPool:SubmitChunkJob(Cx, Cz)
    end)

    local Results = VoxelWorkerPool:PollResults(MaxResultsPerPoll)
    for Index = 1, #Results do
        local Result = Results[Index]
        if Result.Kind == "chunk" and VoxelStreamer:MarkUnloadedIfStale(Result.ChunkX, Result.ChunkZ) then
            PendingChunkUploadCount = PendingChunkUploadCount + 1
            PendingChunkUploads[PendingChunkUploadCount] = Result
        end
    end

    local Budget = love.timer.getTime() + ChunkUploadBudgetSeconds
    local Processed = 0
    local MapDirty = false

    while Processed < PendingChunkUploadCount and love.timer.getTime() < Budget do
        Processed = Processed + 1
        local Result = PendingChunkUploads[Processed]
        if VoxelStreamer:MarkUnloadedIfStale(Result.ChunkX, Result.ChunkZ) then
            UploadChunkToTexture(Result.ChunkX, Result.ChunkZ, Result.VoxelData, Result.MaterialData)
            MapDirty = true
            VoxelStreamer:MarkLoaded(Result.ChunkX, Result.ChunkZ)
        end
    end

    if MapDirty then ChunkStateImage:replacePixels(ChunkStateImageData) end

    if Processed > 0 then
        local Remaining = PendingChunkUploadCount - Processed
        for Index = 1, Remaining do
            PendingChunkUploads[Index] = PendingChunkUploads[Processed + Index]
        end
        for Index = Remaining + 1, PendingChunkUploadCount do
            PendingChunkUploads[Index] = nil
        end
        PendingChunkUploadCount = Remaining
    end
end

function love.keypressed(Key)
    if Key == "escape" then love.event.quit() end
    if Key == "f11" then
        local Fullscreen = love.window.getFullscreen()
        love.window.setFullscreen(not Fullscreen, "desktop")
        local Width, Height = love.graphics.getDimensions()
        RebuildCanvases(Width, Height)
    end
    Keys[Key] = true
end

function love.keyreleased(Key) Keys[Key] = nil end

function love.mousemoved(_, _, Dx, Dy)
    local Sensitivity = 0.001
    Camera.TargetCFrame.Rotation[1] = Camera.TargetCFrame.Rotation[1] + Dx * Sensitivity
    Camera.TargetCFrame.Rotation[2] = Camera.TargetCFrame.Rotation[2] - Dy * Sensitivity
    local PitchLimit = math.pi / 2 - 0.05
    Camera.TargetCFrame.Rotation[2] = math.max(-PitchLimit, math.min(PitchLimit, Camera.TargetCFrame.Rotation[2]))
end

local Performance, Framerate = 0, 0

function love.update(DeltaTime)
    local CamChunkX, CamChunkZ = GetCameraChunk()
    VoxelStreamer:Update(CamChunkX, CamChunkZ)

    local StreamStartTime = love.timer.getTime()
    PumpVoxelStreaming()
    StreamFrameMs = (love.timer.getTime() - StreamStartTime) * 1000

    local LerpFactor = 1 - math.exp(-2 * DeltaTime)
    Framerate = Fabric.Lerp(Framerate, DeltaTime > 0 and (1 / DeltaTime) or 0, LerpFactor)
    Performance = Framerate / (Flags.refreshrate or 60) * 100
    local MoveSpeed = 64 * DeltaTime
    local MoveX, MoveZ = 0, 0
    if Keys["w"] then MoveZ = MoveZ - MoveSpeed end
    if Keys["s"] then MoveZ = MoveZ + MoveSpeed end
    if Keys["a"] then MoveX = MoveX - MoveSpeed end
    if Keys["d"] then MoveX = MoveX + MoveSpeed end
    local Yaw = Camera.TargetCFrame.Rotation[1] or 0
    local CosYaw = math.cos(Yaw)
    local SinYaw = math.sin(Yaw)
    Camera.TargetCFrame.Position[1] = Camera.TargetCFrame.Position[1] + (MoveX * CosYaw - MoveZ * SinYaw)
    Camera.TargetCFrame.Position[3] = Camera.TargetCFrame.Position[3] + (MoveX * SinYaw + MoveZ * CosYaw)
    if Keys["e"] then Camera.TargetCFrame.Position[2] = Camera.TargetCFrame.Position[2] + MoveSpeed end
    if Keys["q"] then Camera.TargetCFrame.Position[2] = Camera.TargetCFrame.Position[2] - MoveSpeed end
    local CameraLerpFactor = 1 - math.exp(-14 * DeltaTime)
    Camera.CFrame.Position = Fabric.LerpProperty(Camera.CFrame.Position, Camera.TargetCFrame.Position, CameraLerpFactor)
    Camera.CFrame.Rotation = Fabric.LerpProperty(Camera.CFrame.Rotation, Camera.TargetCFrame.Rotation, CameraLerpFactor)
end

function love.draw()
    local Width, Height = love.graphics.getDimensions()
    if RenderCanvas:getWidth() ~= Width or RenderCanvas:getHeight() ~= Height then RebuildCanvases(Width, Height) end
    local PrevCanvas = love.graphics.getCanvas()
    local PrevBlendMode, PrevBlendAlphaMode = love.graphics.getBlendMode()
    love.graphics.setCanvas(RenderCanvas)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)

    local AnchorX, AnchorZ = VoxelStreamer.AnchorX, VoxelStreamer.AnchorZ

    local GpuStartTime = love.timer.getTime()

    PathTracerShader:Bind({
        CameraPosition = { Camera.CFrame.Position[1], Camera.CFrame.Position[2], Camera.CFrame.Position[3] },
        CameraRotation = { Camera.CFrame.Rotation[1], Camera.CFrame.Rotation[2], 0 },
        ScreenDimensions = { Width, Height },

        VoxelGrid = VoxelTexture3D,
        MaterialGrid = MaterialTexture3D,
        BrickGrid = BrickTexture3D,
        BrickSize = BrickSize,
        BrickResolution = { BrickResolutionX, BrickResolutionY, BrickResolutionZ },
        GridResolution = { GridResolutionX, GridResolutionY, GridResolutionZ },
        LoadedMin = { (AnchorX - ChunkRadius) * 16, 0, (AnchorZ - ChunkRadius) * 16 },
        LoadedMax = { (AnchorX + ChunkRadius + 1) * 16, GridResolutionY, (AnchorZ + ChunkRadius + 1) * 16 },
        ChunkStateMap = ChunkStateImage,
        TextureChunkSpan = TextureChunkSpan,

        SunDirection = SunDirection,
        SunColor = SunColor,
        VoxelSize = VoxelSize,
        ChunkBaseY = ChunkBaseY,

        MaxRenderDistance = 64.0 * 256.0,
    })
    love.graphics.rectangle("fill", 0, 0, Width, Height)
    PathTracerShader:Unbind()

    love.graphics.setCanvas(PrevCanvas)
    GpuFrameMs = (love.timer.getTime() - GpuStartTime) * 1000

    love.graphics.setBlendMode(PrevBlendMode, PrevBlendAlphaMode)
    love.graphics.setColor(1, 1, 1, 1)

    PathTracerShader:BindPresent()
    love.graphics.draw(RenderCanvas, 0, 0)
    PathTracerShader:UnbindPresent()

    Gui:Flex({ 4, 4 }, { Gap = 4, Padding = 0, Direction = "row" }, {
        function(Pos) return Gui:DrawText(string.format("Framerate: %06.1f", Framerate), Pos, TextColor, "left", { Color = BackgroundColor, Padding = 4 }) end,
        function(Pos) return Gui:DrawText(string.format("Performance: %06.1f%s", Performance, "%"), Pos, TextColor, "left", { Color = BackgroundColor, Padding = 4 }) end,
        function(Pos)
            local Px, Py, Pz = Camera.CFrame.Position[1], Camera.CFrame.Position[2], Camera.CFrame.Position[3]
            local Rx, Ry = math.deg(Camera.CFrame.Rotation[1] or 0) % 360, math.deg(Camera.CFrame.Rotation[2] or 0)
            return Gui:DrawText(string.format("%03.0f,%03.0f,%03.0f ~ %03.0f,%03.0f", Px, Py, Pz, Rx, Ry), Pos, TextColor, "left", { Color = BackgroundColor, Padding = 4 })
        end,
        function(Pos)
            return Gui:DrawProgress(
            { Pos[1], Pos[2] + 1 }, { 128, 20 }, collectgarbage("count") / math.pow(2, 14),
            { Text = string.format("%05.2fGB", collectgarbage("count") / 1024) }
        ) end,
    })
    Gui:DrawImage("Assets/Images/Cursor.png", {Width / 2, Height / 2}, {24, 24}, Color.FromRGBA(255, 255, 255))
end

function love.quit()
    if VoxelWorkerPool then VoxelWorkerPool:Shutdown() end
    return false
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg)) end
    if love.timer then love.timer.step() end
    local EventPump, EventPoll, Handlers, QuitHandler, TimerStep = love.event and love.event.pump, love.event and love.event.poll, love.handlers, love.quit, love.timer and love.timer.step
    local Graphics, IsActive, Origin, Clear, Present = love.graphics, love.graphics and love.graphics.isActive, love.graphics and love.graphics.origin, love.graphics and love.graphics.clear, love.graphics and love.graphics.present
    local DeltaTime = 0
    return function()
        if EventPump then
            EventPump()
            for Name, Ax, Bx, Cx, Dx, Ex, Fx in EventPoll() do
                if Name == "quit" then if not QuitHandler or not QuitHandler() then return Ax or 0 end end
                Handlers[Name](Ax, Bx, Cx, Dx, Ex, Fx)
            end
        end
        if TimerStep then DeltaTime = TimerStep() end
        if love.update then love.update(DeltaTime) end
        if IsActive and IsActive() then
            Origin()
            Clear()
            if love.draw then love.draw() end
            if love.present then love.present() else Present() end
        end
    end
end