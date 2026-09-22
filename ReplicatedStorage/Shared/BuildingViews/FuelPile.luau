-- Prompt view of the firewood pile: one visit puts one log into the player's hands. The log is then
-- carried to an oven, which is where it actually turns into fuel (Kinds/Station.Refuel).

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local FuelPile = {}

--[[ Handling ]]--
function FuelPile.Describe(context: Types.Context): Types.PromptState
	local held = context.Held()
	local label = BuildingsConfig.Kinds[context.Kind].Label

	-- Saying so beats a silent "hands full" after the press: a log is worth nothing until it is
	-- carried to an oven.
	if held and held.Kind == "Fuel" then
		return { Label = "Take to oven" }
	end

	return {
		Label = label,
		Action = "Take a log",
		Fire = function()
			Bus.Kitchen.TakeFirewood:Fire(context.PropId)
		end,
	}
end

return FuelPile
