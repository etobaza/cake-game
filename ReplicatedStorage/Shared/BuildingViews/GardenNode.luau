--!strict
-- Prompts only. GardenWorld owns authored geometry for all observers.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local AnimalCare = require(_Shared.AnimalCare)
local CarryPolicy = require(_Shared.CarryPolicy)
local Config = require(_Shared.Configs.Garden)
local Ingredients = require(_Shared.Configs.Registries.Ingredients)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local GardenNode = {}

--[[ Handling ]]--
function GardenNode.Describe(context: Types.Context): Types.PromptState
	local source = Config.Sources[context.PropId]
	local group = source and context.Cloud({ "Garden", source.Group })
	local node = group and group[context.PropId]
	if not node then
		return { Label = "Not built" }
	end
	local ingredient = Ingredients:Get(source.Produce)
	local name = if ingredient then ingredient.name else source.Produce
	local label = name
	if source.Care == "Animal" and context.AnimalAction == "Brush" then
		label = if source.Produce == "milk" then "Cow" else "Chickens"
	end
	local day = context.Session("Day")
	if not day or day.Phase == "Summary" then
		return { Label = label, Action = "Closed" }
	end
	if node.CareUntil > 0 then
		return { Label = label, Action = `Caring {context.Seconds(node.CareUntil)}s` }
	end
	local held = context.Held()
	if
		source.Capacity == 1
		and context.AnimalAction ~= "Brush"
		and held
		and held.Kind == "Ingredient"
		and held.Id == source.Produce
		and held.SourceId == context.PropId
		and node.Stock == 0
	then
		return {
			Label = name,
			Action = "Put back",
			Fire = function(): ()
				Bus.Garden.Harvest:Fire(context.PropId)
			end,
		}
	end
	if source.Care == "Animal" and context.AnimalAction == "Brush" then
		if held then
			return { Label = label, Action = "Hands full" }
		end
		return {
			Label = label,
			Action = "Brush",
			Fire = function(): ()
				Bus.Garden.Brush:Fire(context.PropId)
			end,
		}
	end
	if source.Care == "Animal" and context.AnimalAction == "Harvest" then
		if node.Stock == 0 then
			return { Label = label }
		end
		if held and not CarryPolicy.CanReplace(held) then
			return { Label = label, Action = "Hands full" }
		end
		return {
			Label = label,
			Action = "Harvest",
			Fire = function(): ()
				Bus.Garden.Harvest:Fire(context.PropId)
			end,
		}
	end
	local plant = source.Care == "Plant"
	local dry = node.CareRemaining <= 0 and node.CleanDay ~= context.Cloud({ "Day" })
	-- A watering can selects care even while fruit is ready. Empty hands select ripe produce first.
	local canWater = plant and held and held.Kind == "Tool" and held.Id == "watering_can"
	local canBrush = source.Care == "Animal"
		and not held
		and node.Stock == 0
		and AnimalCare.Cleanliness(node, context.Cloud({ "Day" })) < 1
	if canWater or canBrush then
		local action = if plant then "Water" else "Brush"
		return {
			Label = label,
			Action = action,
			Fire = function(): ()
				Bus.Garden[action]:Fire(context.PropId)
			end,
		}
	end
	if node.Stock > 0 and (not held or CarryPolicy.CanReplace(held)) then
		return {
			Label = label,
			Action = "Harvest",
			Fire = function(): ()
				Bus.Garden.Harvest:Fire(context.PropId)
			end,
		}
	end
	if held then
		return { Label = label, Action = "Hands full" }
	end
	if dry and source.Care ~= "Hive" then
		return { Label = label, Action = if plant then "Needs water" else "Needs brushing" }
	end
	local levels = context.Cloud({ "Base", "Upgrades" }) or {}
	local speed = if plant and (levels.garden_beehive or 0) > 0 then 1 + Config.PollinationBonus else 1
	return { Label = label, Action = `Growing {math.ceil(node.GrowRemaining / speed)}s` }
end
return GardenNode
