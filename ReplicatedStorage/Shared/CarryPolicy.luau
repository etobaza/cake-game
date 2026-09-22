--!strict
-- Infinite dispenser ingredients can return to their source when another pickup succeeds.
-- Shared by inventory and prompts so an occupied hand offers the same actions on both sides.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local GameTypes = require(_Shared.GameTypes)
local Ingredients = require(_Shared.Configs.Registries.Ingredients)

--[[ Tables ]]--
local CarryPolicy = {}

--[[ Handling ]]--
function CarryPolicy.CanReplace(item: GameTypes.ItemStack?): boolean
	return item ~= nil and item.Kind == "Ingredient" and item.SourceId ~= nil and Ingredients:IsInfinite(item.Id)
end

function CarryPolicy.CanReturn(item: GameTypes.ItemStack?, sourceId: string, ingredientId: string): boolean
	return item ~= nil and CarryPolicy.CanReplace(item) and item.SourceId == sourceId and item.Id == ingredientId
end

return CarryPolicy
