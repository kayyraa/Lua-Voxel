local Fabric = {}

--- @param Alpha number
--- @param Beta number
--- @param Time number
--- @return number
local function Lerp(Alpha, Beta, Time) return Alpha + (Beta - Alpha) * Time end

--- @param Time number
--- @return number
function Fabric.Fade(Time) return Time * Time * Time * (Time * (Time * 6 - 15) + 10) end

function Fabric.Lerp(Alpha, Beta, Time) return Lerp(Alpha, Beta, Time) end

--- @param Alpha table | number
--- @param Beta table | number
--- @param Time number
--- @return table | number | nil
function Fabric.LerpProperty(Alpha, Beta, Time)
    if type(Alpha) == "table" and type(Beta) == "table" then
        local Result = {}
        for Key, Value in pairs(Alpha) do
            local TargetValue = Beta[Key]
            if type(Value) == "number" and type(TargetValue) == "number" then
                Result[Key] = Lerp(Value, TargetValue, Time)
            else
                Result[Key] = Value
            end
        end
        return Result
    end
    if type(Alpha) == "number" and type(Beta) == "number" then return Lerp(Alpha, Beta, Time)
    else return nil end
end

return Fabric