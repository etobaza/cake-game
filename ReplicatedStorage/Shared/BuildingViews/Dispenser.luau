--!strict
-- Prompt view of a pantry dispenser: how much of the ingredient is left and taking one.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local CarryPolicy = require(_Shared.CarryPolicy)
local Ingredients = require(_Configs.Registries.Ingredients)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local Dispenser = {}

--[[ Handling ]]--
function Dispenser.Describe(context: Types.Context): Types.PromptState
	local prefix = BuildingsConfig.Kinds[context.Kind].Prefix
	local ingredientId = string.match(context.PropId, `^{prefix}_(.+)$`)

	local function FireTake(): ()
		Bus.Kitchen.TakeIngredient:Fire(context.PropId)
	end

	local ingredient = ingredientId and Ingredients:Get(ingredientId)
	if not ingredient then
		return { Label = BuildingsConfig.Kinds[context.Kind].Label }
	end

	local held = context.Held()
	if CarryPolicy.CanReturn(held, context.PropId, ingredient.id) then
		return {
			Label = ingredient.name,
			Action = "Put back",
			Fire = function(): ()
				Bus.Kitchen.ReturnIngredient:Fire(context.PropId)
			end,
		}
	end
	if held and not CarryPolicy.CanReplace(held) then
		return { Label = "Hands full" }
	end

	if Ingredients:IsInfinite(ingredientId) then
		return {
			Label = ingredient.name,
			Action = "Take",
			Fire = FireTake,
		}
	end

	local amount = context.Cloud({ "Pantry", ingredientId :: string }) or 0
	if amount == 0 then
		return { Label = `{ingredient.name} x0` }
	end

	return {
		Label = `{ingredient.name} x{amount}`,
		Action = "Take",
		Fire = FireTake,
	}
end

return Dispenser
