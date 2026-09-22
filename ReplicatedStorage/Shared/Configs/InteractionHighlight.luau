--!strict
-- Visible counterparts of invisible interaction volumes. WorldModel remains authoritative for racks.
return {
	Color = Color3.new(1, 1, 1),
	FillTransparency = 1,
	OutlineTransparency = 0,
	DepthMode = Enum.HighlightDepthMode.Occluded,
	Paths = {
		oven_1 = { "1ndFloor", "Kitchen", "Decoration", "Oven" },
		oven_2 = { "1ndFloor", "Kitchen", "Upgrades", " OvenUpgrade", "Upgrade2", "Oven" },
		oven_3 = { "1ndFloor", "Kitchen", "Upgrades", " OvenUpgrade", "Upgrade1", "Oven" },
		freezer_1 = { "1ndFloor", "Kitchen", "Upgrades", "Freezer", "Upgrade" },
		coffee_1 = { "1ndFloor", "Cafe", "Upgrades", "CoffeeMachine", "Upgrade" },
		fuel = { "1ndFloor", "Kitchen", "Upgrades", "FireWood", "Upgrade", "FireWood" },
	} :: { [string]: { string } },
	GardenPath = { "1ndFloor", "Garden", "Upgrades" },
	DisplayPath = { "1ndFloor", "Cafe", "Upgrades", "DisplayCounter" },
	DisplayLedgePath = { "1ndFloor", "Cafe", "Decoration" },
	DisplayLedgeNames = { ["repo "] = true, ["repolarge "] = true } :: { [string]: boolean },
}
