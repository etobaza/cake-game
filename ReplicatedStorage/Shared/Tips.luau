--!strict
-- Pure math of the revenue from one dish. Kept apart: the server computes it, the client shows it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local DayCycleConfig = require(_Configs.DayCycle)
local Economy = require(_Configs.Economy)
local Recipes = require(_Configs.Registries.Recipes)

export type SaleParams = {
	recipeId: string,
	-- Share of the customer patience left at the moment of serving, 0..1.
	patienceLeft: number,
	-- Customer type multiplier.
	customerMultiplier: number,
	-- The player's TipMult stat.
	tipStat: number,
	-- Day menu: the more varied it is, the higher the tips.
	menuSize: number,
	-- The recipe was unlocked recently and still gives a temporary bonus.
	isNewRecipe: boolean,
}

--[[ Tables ]]--
local Tips = {}

--[[ Handling ]]--
-- Total = dish price + tip. Below TipPatienceFloor there is no tip, but the price is always paid.
function Tips.GetSaleValue(params: SaleParams): number
	local recipe = Recipes:Get(params.recipeId)
	if not recipe then
		return 0
	end

	local floor = Economy.TipPatienceFloor
	local speed = math.clamp((params.patienceLeft - floor) / (1 - floor), 0, 1)

	local rate = Economy.TipFraction * speed
	rate += math.max(params.menuSize - DayCycleConfig.MenuMin, 0) * Economy.VarietyBonusPerRecipe

	if recipe.vegan then
		rate += Economy.VeganBonus
	end

	if recipe.glutenFree then
		rate += Economy.GlutenFreeBonus
	end

	if params.isNewRecipe then
		rate += Economy.NewRecipeBonus
	end

	local tip = recipe.price * rate * params.customerMultiplier * params.tipStat

	return math.round((recipe.price + tip) * 100) / 100
end

return Tips
