local Color = require("Services.Color")
local Gui = {}

--- @param Text string
--- @param Position number[]
--- @param Color number[]
--- @param Align string | nil
--- @param Background table | nil
--- @return number, number
function Gui:DrawText(Text, Position, Color, Align, Background)
    local Tw = love.graphics.getFont():getWidth(Text)
    local Th = love.graphics.getFont():getHeight()
    local Padding = Background and Background.Padding or 0
    local Rw = Tw + Padding * 2
    local Rh = Th + Padding * 2

    if Background then
        love.graphics.setColor(Background.Color[1], Background.Color[2], Background.Color[3], Background.Color[4])
        love.graphics.rectangle("fill", Position[1], Position[2], Rw, Rh)
    end

    love.graphics.setColor(Color[1], Color[2], Color[3], Color[4])
    love.graphics.printf(Text, Position[1] + Padding, Position[2] + Padding, Tw, Align or "left")
    return Rw, Rh
end

--- @param Position number[]
--- @param Size number[]
--- @param Color number[]
--- @param Outline table[] | nil
--- @param Draw string | nil
--- @return number, number
function Gui:DrawRect(Position, Size, Color, Outline, Draw)
    love.graphics.setColor(Color[1] or 1, Color[2] or 1, Color[3] or 1, Color[4] or 1)
    love.graphics.rectangle(Draw or "fill", Position[1] or 0, Position[2] or 0, Size[1] or 0, Size[2] or 0)
    if Outline then
        local lw = love.graphics.getLineWidth()

        love.graphics.setColor(Outline.Color)

        love.graphics.setLineWidth(Outline.Thickness or 1)

        love.graphics.rectangle(
            "line",
            Position[1] or 0,
            Position[2] or 0,
            Size[1] or 0,
            Size[2] or 0
        )

        love.graphics.setColor(Outline.Color)
        love.graphics.setLineWidth(lw)
    end
    return Size[1] or 0, Size[2] or 0
end

--- @param Position number[]
--- @param Radius number
--- @param Angle number[]
--- @param Segments number
--- @param Color number[]
--- @param Draw string | nil
--- @return number, number
function Gui:DrawArch(Position, Radius, Angle, Segments, Color, Draw)
    love.graphics.setColor(Color[1] or 1, Color[2] or 1, Color[3] or 1, Color[4] or 1)
    love.graphics.arc(Draw or "fill", Position[1] or 0, Position[2] or 0, Radius or 0, Angle[1] or 0, Angle[2] or 0, Segments or 64)
    return Radius or 0, Radius or 0
end

local Images = {}

---@param Path string
---@param Position number[]
---@param Size number[]
---@param Color number[]
---@param Outline table | nil
---@return number, number
function Gui:DrawImage(Path, Position, Size, Color, Outline)
    local Image = Images[Path]

    if not Image then
        Image = love.graphics.newImage(Path)
        Images[Path] = Image
    end

    local ImgW, ImgH = Image:getWidth(), Image:getHeight()

    local Scale = math.min(Size[1] / ImgW, Size[2] / ImgH)
    local ScaleX, ScaleY = Scale, Scale

    local OriginX, OriginY = ImgW / 2, ImgH / 2
    local Px, Py, Rotation = Position[1] or 0, Position[2] or 0, Position[3] or 0

    if Outline then
        local Thickness = Outline.Thickness or 2
        local OutlineColor = Outline.Color or { 0, 0, 0, 1 }

        love.graphics.setColor(OutlineColor[1] or 0, OutlineColor[2] or 0, OutlineColor[3] or 0, OutlineColor[4] or 1)

        local Steps = Outline.Steps or 8
        for Index = 1, Steps do
            local Angle = (Index / Steps) * math.pi * 2

            local Ox = (math.cos(Angle) * Thickness) / ScaleX
            local Oy = (math.sin(Angle) * Thickness) / ScaleY

            love.graphics.draw(
                Image,
                Px, Py, Rotation,
                ScaleX, ScaleY,
                OriginX - Ox, OriginY - Oy
            )
        end
    end

    love.graphics.setColor(Color[1] or 1, Color[2] or 1, Color[3] or 1, Color[4] or 1)
    love.graphics.draw(
        Image,
        Px, Py, Rotation,
        ScaleX, ScaleY,
        OriginX, OriginY
    )

    return ImgW * ScaleX, ImgH * ScaleY
end

--- @param Position1 number[]
--- @param Position2 number[]
--- @param Thickness number
--- @param Color number[]
--- @return number, number
function Gui:DrawLine(Position1, Position2, Thickness, Color)
    love.graphics.setColor(Color[1] or 1, Color[2] or 1, Color[3] or 1, Color[4] or 1)
    love.graphics.setLineWidth(Thickness or 1)
    love.graphics.line(Position1[1] or 0, Position1[2] or 0, Position2[1] or 0, Position2[2] or 0)
    return math.abs(Position2[1] - Position1[1]), math.abs(Position2[2] - Position1[2])
end

--- @param Position number[]
--- @param Size number[] Sx
--- @param Progress number 0-1
--- @param Options table[] | nil
function Gui:DrawProgress(Position, Size, Progress, Options)
    local Px, Py = Position[1], Position[2]
    local W, H = Size[1], Size[2]
    local EmptyColor = Options and Options.Empty or Color.FromRGBA(0, 0, 0, 0.5)
    local FullColor = Options and Options.Full or Color.FromRGBA(0, 0, 0)
    local OutlineColor = Options and Options.Outline or Color.FromRGBA(0, 0, 0)
    local Thickness = Options and Options.Thickness or 2

    local CurrentFill = math.max(0, math.min(W, W * Progress))

    love.graphics.setColor(EmptyColor)
    love.graphics.rectangle("fill", Px, Py, W, H)

    love.graphics.setColor(FullColor)
    love.graphics.rectangle("fill", Px, Py, CurrentFill, H)

    love.graphics.setLineWidth(Thickness)
    love.graphics.setColor(OutlineColor)
    love.graphics.rectangle("line", Px, Py, W, H)
    love.graphics.setLineWidth(1)

    if Options and Options.Text then
        Gui:DrawText(Options.Text, { Px + 4, Py + 4 }, Color.FromRGBA(255, 255, 255), "left")
    end

    return W, H
end

--- @param Table table
--- @param Options table
function Gui:DrawGraph(Table, Options)
    local Thickness = Options.Thickness or 1
    local Color = Options.Color or { 1, 1, 1, 1 }
    local MpColor = Options.MpColor or Color

    local Px = (Options.Position and Options.Position[1]) or 0
    local Py = (Options.Position and Options.Position[2]) or 0
    local Sx = Options.Width or 0
    local Sy = Options.Height or 0

    local Mn = Options.Mn or 0
    local Mx = Options.Mx or 1
    local Mp = Options.Mp

    local Range = Mx - Mn
    if Range <= 0 then Range = 1 end

    if Mp ~= nil then
        local Y = (Mp - Mn) / Range
        Y = Py + Sy - math.max(0, math.min(Sy, Y * Sy))

        local MinX, MaxX = math.huge, -math.huge
        for _, Point in ipairs(Table) do
            MinX = math.min(MinX, Point[1])
            MaxX = math.max(MaxX, Point[1])
        end

        MinX = math.max(Px, MinX)
        MaxX = math.min(Px + Sx, MaxX)

        local Dash = 8
        for X = MinX, MaxX, Dash * 2 do
            self:DrawLine(
                { X, Y },
                { math.min(X + Dash, MaxX), Y },
                Options.MpThickness,
                MpColor
            )
        end
    end

    local Algorithm = Options.Algorithm or function(Gui, Points)
        for Index = 1, #Points - 1 do
            local P1 = Points[Index]
            local P2 = Points[Index + 1]

            local Px1 = math.max(Px, math.min(Px + Sx, P1[1]))
            local Px2 = math.max(Px, math.min(Px + Sx, P2[1]))

            local Py1 = (P1[2] - Mn) / Range
            local Py2 = (P2[2] - Mn) / Range

            Py1 = Py + Sy - math.max(0, math.min(Sy, Py1 * Sy))
            Py2 = Py + Sy - math.max(0, math.min(Sy, Py2 * Sy))

            local T = ((Py + Sy - Py1) + (Py + Sy - Py2)) * 0.5 / Sy
            local Alpha = (Color[4] or 1) * T

            Gui:DrawLine(
                { Px1, Py1 },
                { Px2, Py2 },
                Thickness,
                { Color[1], Color[2], Color[3], Alpha }
            )
        end
    end

    Algorithm(self, Table)
end

function Gui:Graph(MaxSamples)
    local self = {
        Data = {},
        Max = MaxSamples or 120
    }

    function self:Add(Value)
        table.insert(self.Data, Value)
        if #self.Data > self.Max then table.remove(self.Data, 1) end
    end

    function self:GetMax()
        local Vm = 20
        for _, Value in ipairs(self.Data) do if Value > Vm then Vm = Value end end
        return Vm
    end

    function self:GetPoints(Px, Py, Width, MaxSamples)
        local Points = {}
        for _, Value in ipairs(self.Data) do
            Points[_] = { Px + (_ - 1) / (MaxSamples - 1) * Width, Value }
        end
        return Points
    end

    return self
end

--- @param Path string
--- @param Size number
function Gui:Font(Path, Size)
    love.graphics.setFont(love.graphics.newFont(Path, Size))
end

--- @param Position number[]
--- @param Config table
--- @param Elements function[]
function Gui:Flex(Position, Config, Elements)
    local Gap = Config.Gap or 0
    local Padding = Config.Padding or 0
    local Direction = Config.Direction or "row"

    local CurrentX = Position[1] + Padding
    local CurrentY = Position[2] + Padding

    for _ = 1, #Elements do
        local ElementDrawFunction = Elements[_]
        local Width, Height = ElementDrawFunction({ CurrentX, CurrentY })

        if Direction == "row" then
            CurrentX = CurrentX + Width + Gap
        elseif Direction == "column" then
            CurrentY = CurrentY + Height + Gap
        end
    end
end

return Gui