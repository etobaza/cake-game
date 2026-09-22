--!strict
-- Food dimensions and attachment names. FoodSurface attachments live on the reference anchors.
local FoodPresentation = {
	SurfaceAttachment = "FoodSurface",
	HandAttribute = "CarriedFood",
	PreviewFieldOfView = 35,
	TraySize = Vector3.new(2.6, 0.2, 2.6),
	FoodSize = Vector3.new(2.1, 1.9, 2.1),
	SurfaceFoodSize = Vector3.new(2.1, 2.2, 2.1),
	-- The authored oven anchors sit 0.222 studs above the mesh shelf; food uses the carried FoodSize.
	OvenFoodOffset = CFrame.new(0, -0.222, -0.3),
	DisplayUpgrade = "cafe_display",
	DisplayPedestals = 5,
	TableFoodSize = Vector3.new(1.25, 1.4, 1.25),
	-- Food clears the thin tray floor while keeping its bottom visibly in contact.
	TrayClearance = 0.015,
	-- The support palm sits below the tray center. The carrying animation selects the hand.
	HandOffset = Vector3.new(0, 0.08, 0),
}
return FoodPresentation
