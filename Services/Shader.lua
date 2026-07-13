local Shader = {}
Shader.__index = Shader

local function ReadFile(Path)
    local Contents = love.filesystem.read(Path)
    if not Contents then error("Shader.lua: failed to read " .. Path) end
    return Contents
end

function Shader.New()
    local Self = setmetatable({}, Shader)
    Self.Program = love.graphics.newShader(ReadFile("Assets/Shaders/PathTracer.glsl"))
    Self.PresentProgram = love.graphics.newShader(ReadFile("Assets/Shaders/Present.glsl"))
    return Self
end

local function SendIfPresent(Program, Name, Value)
    if Value ~= nil and Program:hasUniform(Name) then
        Program:send(Name, Value)
    end
end

function Shader:Bind(Params)
    local Program = self.Program

    SendIfPresent(Program, "CameraPosition", Params.CameraPosition)
    SendIfPresent(Program, "CameraRotation", Params.CameraRotation)
    SendIfPresent(Program, "ScreenDimensions", Params.ScreenDimensions)

    SendIfPresent(Program, "VoxelGrid", Params.VoxelGrid)
    SendIfPresent(Program, "MaterialGrid", Params.MaterialGrid)
    SendIfPresent(Program, "BrickGrid", Params.BrickGrid)
    SendIfPresent(Program, "BrickSize", Params.BrickSize)
    SendIfPresent(Program, "BrickResolution", Params.BrickResolution)
    SendIfPresent(Program, "GridResolution", Params.GridResolution)
    SendIfPresent(Program, "LoadedMin", Params.LoadedMin)
    SendIfPresent(Program, "LoadedMax", Params.LoadedMax)
    SendIfPresent(Program, "ChunkStateMap", Params.ChunkStateMap)
    SendIfPresent(Program, "TextureChunkSpan", Params.TextureChunkSpan)

    SendIfPresent(Program, "SunDirection", Params.SunDirection)
    SendIfPresent(Program, "SunColor", Params.SunColor)
    SendIfPresent(Program, "VoxelSize", Params.VoxelSize)
    SendIfPresent(Program, "ChunkBaseY", Params.ChunkBaseY)

    SendIfPresent(Program, "MaxRenderDistance", Params.MaxRenderDistance)

    love.graphics.setShader(Program)
end

function Shader:Unbind()
    love.graphics.setShader()
end

function Shader:BindPresent()
    love.graphics.setShader(self.PresentProgram)
end

function Shader:UnbindPresent()
    love.graphics.setShader()
end

return Shader