--!strict
-- Pure presentation decisions shared by accepted server actions and client views.
--[[ Modules ]]--
local Config = require(script.Parent.Configs.VFX)

--[[ Tables ]]--
local Rules = {}

--[[ Handling ]]--
function Rules.Reaction(kind: string, patienceEndsAt: number, patience: number, now: number): string
	if kind == "Display" then
		return "Singing"
	end
	local elapsed = math.clamp((now - (patienceEndsAt - patience)) / math.max(patience, 0.001), 0, 1)
	if elapsed < Config.PerfectFraction then
		return "Happy"
	end
	if elapsed >= Config.LateFraction then
		return "Angry"
	end
	return "Singing"
end

function Rules.Number(value: any, default: number, minimum: number, maximum: number): number
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return default
	end
	return math.clamp(value, minimum, maximum)
end

return Rules
