--!strict
-- Authored carry models. Ingredients fit the tray; firewood rests between the palms.
export type Entry = { Asset: { string }, MaxSize: Vector3, Rotation: CFrame?, BetweenHands: boolean? }

local CarryPresentation = {
	-- A brief raised arc keeps pickups readable while the destination follows the moving hand.
	PickupSeconds = 0.45,
	PickupArcHeight = 0.8,
	PickupMaxAge = 1.5,
	PickupMaxDistance = 24,
	HandOffset = Vector3.new(0, 0.03, 0),
	OvenSurfaceAttachment = "FuelSurface",
	OvenStackAsset = "OvenFuelStack",
	Items = {
		Fuel = {
			firewood = {
				Asset = { "Ingredients", "log" },
				MaxSize = Vector3.new(2.8, 0.8, 1.4),
				BetweenHands = true,
			},
		},
		Ingredient = {
			flour = { Asset = { "Furniture", "Bag" }, MaxSize = Vector3.new(1.45, 1.8, 1.45) },
			-- The authored kitchen sugar cubes are named Cheese.
			sugar = { Asset = { "Ingredients", "Cheese" }, MaxSize = Vector3.new(0.85, 0.85, 0.85) },
			strawberry = { Asset = { "Ingredients", "Strawberry" }, MaxSize = Vector3.new(0.95, 1.05, 0.95) },
			blueberry = { Asset = { "Ingredients", "Blueberry" }, MaxSize = Vector3.new(0.85, 0.85, 0.85) },
			grape = { Asset = { "Ingredients", "Grape" }, MaxSize = Vector3.new(1, 1.3, 1) },
			carrot = { Asset = { "Ingredients", "Carrot" }, MaxSize = Vector3.new(1, 1.6, 1) },
			lemon = { Asset = { "Ingredients", "Limon" }, MaxSize = Vector3.new(1, 1.2, 1) },
			apple = { Asset = { "Ingredients", "Apple" }, MaxSize = Vector3.new(1, 1.1, 1) },
			cocoa = { Asset = { "Ingredients", "Cocoa" }, MaxSize = Vector3.new(1, 1.3, 1) },
			cherry = { Asset = { "Ingredients", "Cherry" }, MaxSize = Vector3.new(1, 1.1, 1) },
			milk = { Asset = { "Ingredients", "Milk" }, MaxSize = Vector3.new(1, 1.5, 1) },
			egg = { Asset = { "Ingredients", "Egg" }, MaxSize = Vector3.new(0.8, 1, 0.8) },
			honey = { Asset = { "Ingredients", "Honey" }, MaxSize = Vector3.new(1.2, 1, 1.2) },
		},
	} :: { [string]: { [string]: Entry } },
}
return CarryPresentation
