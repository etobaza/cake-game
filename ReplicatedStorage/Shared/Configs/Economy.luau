--!strict
-- Shift economy: what the coins and XP for a served customer are made of.

--[[ Tables ]]--
local Economy = {
	-- Share of the dish price that becomes a tip on a perfectly fast serve.
	TipFraction = 0.35,
	-- Below this share of remaining patience there is no tip at all.
	TipPatienceFloor = 0.2,

	-- Tip bonus for every recipe in the menu above the minimum size.
	VarietyBonusPerRecipe = 0.04,
	-- Bonus for a recently unlocked dish and how many days it lives.
	NewRecipeBonus = 0.25,
	NewRecipeBonusDays = 3,
	-- Bonuses for menu quality.
	VeganBonus = 0.05,
	GlutenFreeBonus = 0.05,

	-- XP per dish follows its price instead of being flat: a lemon cake is four times the work
	-- of a loaf of bread, and a flat reward makes the whole late menu pointless to cook.
	XPPerCoin = 0.35,
	XPMinPerDish = 2,

	XPShiftComplete = 20,
	-- XP penalty for every customer who left with nothing.
	XPLostCustomer = 3,
}

--[[ Handling ]]--
function Economy.GetDishXP(price: number): number
	return math.max(math.round(price * Economy.XPPerCoin), Economy.XPMinPerDish)
end

return Economy
