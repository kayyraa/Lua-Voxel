local Color = {}

--- @param Value number
--- @param Min number
--- @param Max number
--- @return number
local function Clamp(Value, Min, Max)
    return math.min(math.max(Value, Min), Max)
end

--- @param Alpha number
--- @param Beta number
--- @param Time number
--- @return number
local function Lerp(Alpha, Beta, Time)
    return Alpha + (Beta - Alpha) * Time
end

--- @param ColorArray number[]
--- @return number[]
local function ClampColor(ColorArray)
    return {
        Clamp(ColorArray[1], 0, 1),
        Clamp(ColorArray[2], 0, 1),
        Clamp(ColorArray[3], 0, 1),
        Clamp(ColorArray[4], 0, 1)
    }
end

--- @param Cr number
--- @param Cg number
--- @param Cb number
--- @param Al number | nil
--- @return number[]
function Color.FromRGBA(Cr, Cg, Cb, Al)
    return ClampColor({ Cr / 255, Cg / 255, Cb / 255, Al or 1 })
end

---@param Alpha number[]
---@param Beta number[]
---@param Gamma number
---@return number[]
function Color.Mix(Alpha, Beta, Gamma)
    Gamma = math.max(0, math.min(1, Gamma))
    return {
        Alpha[1] + (Beta[1] - Alpha[1]) * Gamma,
        Alpha[2] + (Beta[2] - Alpha[2]) * Gamma,
        Alpha[3] + (Beta[3] - Alpha[3]) * Gamma,
        Alpha[4] + (Beta[4] - Alpha[4]) * Gamma,
    }
end

--- @param Cr number
--- @param Cg number
--- @param Cb number
--- @param Al number
--- @return number[]
function Color.Float(Cr, Cg, Cb, Al)
    return ClampColor({ Cr, Cg, Cb, Al })
end

--- @param Alpha number[]
--- @param Beta number[]
--- @param Time number
--- @return number[]
function Color.Lerp(Alpha, Beta, Time)
    return {
        Lerp(Alpha[1], Beta[1], Time),
        Lerp(Alpha[2], Beta[2], Time),
        Lerp(Alpha[3], Beta[3], Time),
        Lerp(Alpha[4], Beta[4], Time)
    }
end

return Color