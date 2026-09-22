--!strict
-- Bowl-only presentation of accepted ingredients, adapted to the three authored Cake meshes.
-- ingredient1 is a soft mound, ingredient2 a dollop, and ingredient3 the artist's loose crumbs.
-- Colors describe the ingredient inside the bowl, without its container, skin or shared atlas.
local MixerIngredients = {
	-- The catalog needs at most four portions; fixed edge slots leave the center clear.
	PortionSize = Vector3.new(1.1, 0.9, 1.1),
	SlotCount = 4,
	Radius = 0.8,
	Height = 0.12,
	Entries = {
		flour = { Asset = "ingredient1", Color = Color3.fromRGB(255, 248, 231) },
		-- The carried golden caramel cube is the existing sugar ingredient (authored as Cheese).
		sugar = { Asset = "ingredient3", Color = Color3.fromRGB(226, 151, 44) },
		milk = { Asset = "ingredient1", Color = Color3.fromRGB(255, 253, 248) },
		egg = { Asset = "ingredient2", Color = Color3.fromRGB(255, 184, 35) },
		honey = { Asset = "ingredient2", Color = Color3.fromRGB(235, 155, 27) },
		cocoa = { Asset = "ingredient3", Color = Color3.fromRGB(104, 57, 35) },
		strawberry = { Asset = "ingredient1", Color = Color3.fromRGB(222, 65, 73) },
		blueberry = { Asset = "ingredient1", Color = Color3.fromRGB(78, 83, 173) },
		grape = { Asset = "ingredient1", Color = Color3.fromRGB(135, 72, 163) },
		carrot = { Asset = "ingredient3", Color = Color3.fromRGB(243, 133, 45) },
		apple = { Asset = "ingredient3", Color = Color3.fromRGB(243, 222, 157) },
		lemon = { Asset = "ingredient3", Color = Color3.fromRGB(249, 216, 67) },
		cherry = { Asset = "ingredient1", Color = Color3.fromRGB(176, 40, 58) },
	} :: { [string]: { Asset: string, Color: Color3 } },
}

return MixerIngredients
