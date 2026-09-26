--!strict
-- Cleanliness follows Lemon Cake's DirtMaterial curve; one means completely clean.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Garden)

local AnimalCare = {}

-- `day` is nil until the replicated day arrives; nothing matches it, so the curve decides.
function AnimalCare.Cleanliness(state: any, day: number?): number
	if state.CleanDay == day then
		return 1
	end
	return math.clamp(state.CareRemaining / (Config.CleanSeconds - Config.BrushCleanHoldSeconds), 0, 1)
end

function AnimalCare.Brushing(state: any, day: number, now: number, duration: number): number
	local clean = AnimalCare.Cleanliness(state, day)
	if state.CareUntil > 0 then
		clean = math.max(clean, math.clamp(1 - (state.CareUntil - now) / duration, 0, 1))
	end
	return clean
end

return AnimalCare
