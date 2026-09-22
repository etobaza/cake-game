--!strict
-- Care strategies consume active play time; no offline wall-clock deadlines.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Garden)

--[[ Tables ]]--
local GardenCare = {}

GardenCare.Plant = {
	CanCare = function(held: any): boolean
		return held ~= nil and held.Kind == "Tool" and held.Id == "watering_can"
	end,
	Complete = function(state: any, _day: number, upgrades: any, player: Player): ()
		state.CareRemaining = Config.WaterSeconds * upgrades:GetStat(player, "WaterDurationMult")
	end,
	Step = function(state: any, seconds: number, _day: number, upgrades: any, player: Player): number
		if upgrades:HasStat(player, "AutoWater") then
			if state.CareRemaining ~= Config.WaterSeconds then
				state.CareRemaining = Config.WaterSeconds
			end
			return seconds
		end
		local available = math.min(seconds, state.CareRemaining)
		if available > 0 then
			state.CareRemaining = math.max(0, state.CareRemaining - seconds)
		end
		return available
	end,
	Speed = function(upgrades: any, player: Player): number
		return upgrades:GetStat(player, "GrowthSpeedMult")
	end,
}

GardenCare.Animal = {
	CanCare = function(held: any): boolean
		return held == nil
	end,
	Complete = function(state: any, day: number, upgrades: any, player: Player): ()
		state.CareRemaining = Config.CleanSeconds
		state.CleanDay = if upgrades:HasStat(player, "AnimalBrush") then day else 0
	end,
	Step = function(state: any, seconds: number, day: number, _upgrades: any, _player: Player): number
		if state.CleanDay == day then
			return seconds
		end
		local available = math.min(seconds, state.CareRemaining)
		if available > 0 then
			state.CareRemaining = math.max(0, state.CareRemaining - seconds)
		end
		return available
	end,
	Speed = function(_upgrades: any, _player: Player): number
		return 1
	end,
}

GardenCare.Hive = {
	CanCare = function(_held: any): boolean
		return false
	end,
	Complete = function(_state: any, _day: number, _upgrades: any, _player: Player): () end,
	Step = function(_state: any, seconds: number, _day: number, _upgrades: any, _player: Player): number
		return seconds
	end,
	Speed = function(_upgrades: any, _player: Player): number
		return 1
	end,
}

return GardenCare
