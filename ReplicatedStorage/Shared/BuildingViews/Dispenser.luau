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
local IngredientCard = require(_Shared.UI.IngredientCard)
local Ingredients = require(_Configs.Registries.Ingredients)
local Recipes = require(_Configs.Registries.Recipes)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local Dispenser = {}

--[[ Private Functions ]]--
-- Units of the ingredient the selected recipe's bowl still lacks; 0 with no recipe chosen.
local function Lacking(context: Types.Context, ingredientId: string): number
	local cooking = context.Session("Cooking")
	local recipe = cooking and cooking.SelectedRecipeId and Recipes:Get(cooking.SelectedRecipeId)
	local needed = recipe and recipe.ingredients[ingredientId]
	if not recipe or not needed then
		return 0
	end
	local loaded = IngredientCard.Loaded(context.Session("Stations"), Recipes:GetStartStation(recipe))
	return needed - (loaded[ingredientId] or 0)
end

--[[ Handling ]]--
-- The trays stand beside the mixer and share its key, so they offer Take only while the chosen
-- recipe still needs their staple; otherwise the mixer's own prompt is the only one there.
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
	-- An ingredient the bowl still takes belongs in the mixer, so Add keeps the key.
	if held and held.Kind == "Ingredient" and Lacking(context, held.Id) > 0 then
		return { Label = ingredient.name }
	end
	if CarryPolicy.CanReturn(held, context.PropId, ingredient.id) then
		return {
			Label = ingredient.name,
			Action = "Put back",
			Fire = function(): ()
				Bus.Kitchen.ReturnIngredient:Fire(context.PropId)
			end,
		}
	end
	if Lacking(context, ingredient.id) <= 0 then
		return { Label = ingredient.name }
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
