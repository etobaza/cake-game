--!strict
-- Base player values with no upgrades at all. Upgrades add on top (UpgradeHandler).
-- The keys of this table are the only modifier dictionary; the upgrade registry points at them.

--[[ Types ]]--
-- Mirrors the keys of the table below by hand: the type solver in use has no `keyof`, so a new
-- stat must be added in both places.
export type StatKey =
	| "DisplaySlots"
	| "TableCount"
	| "TipMult"
	| "AssistantSlots"
	| "MixerCount"
	| "OvenCount"
	| "FreezerCount"
	| "CoffeeCount"
	| "FuelBurnSeconds"
	| "MixSpeedMult"
	| "BurnTimeMult"
	| "PlotCount"
	| "TreeCount"
	| "AnimalCount"
	| "GrowthSpeedMult"
	| "HarvestAmount"
	| "AutoWater"
	| "WaterDurationMult"
	| "AnimalBrush"
	| "CartEnabled"
	| "HandsLimit"
	| "WalkSpeed"
	| "RunSpeed"

--[[ Tables ]]--
local BaseStats = {
	-- Cafe
	DisplaySlots = 1,
	TableCount = 1,
	TipMult = 1,
	AssistantSlots = 0,

	-- Kitchen
	MixerCount = 1,
	OvenCount = 1,
	FreezerCount = 0,
	CoffeeCount = 0,
	FuelBurnSeconds = 90,
	MixSpeedMult = 1,
	BurnTimeMult = 1,

	-- Garden: every bed, tree and animal is bought in the shop, so the garden starts empty.
	PlotCount = 0,
	TreeCount = 0,
	AnimalCount = 0,
	GrowthSpeedMult = 1,
	HarvestAmount = 1,
	AutoWater = 0,
	WaterDurationMult = 1,
	AnimalBrush = 0,
	CartEnabled = 0,

	-- Player
	HandsLimit = 1,
	WalkSpeed = 16,
	RunSpeed = 24,
}

return BaseStats
