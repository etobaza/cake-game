--!strict
-- Replicated hinge targets; clients animate the authored leaves between server decisions.
return {
	Tag = "OvenDoorMotion",
	OpenAttribute = "OvenOpenPivot",
	ClosedAttribute = "OvenClosedPivot",
	TargetAttribute = "OvenDoorClosed",
	-- A gentle close has time to accelerate and settle without delaying cooking.
	TravelSeconds = 1.4,
	Dial = {
		-- Measured against the authored oven mesh and the resting ClockHand pivot.
		ReferenceBodyWidth = 6.475455,
		Radius = 0.944855,
		CenterHeight = 0.063473,
		FaceDepth = 0.073852,
		SurfaceLift = 0.012,
		SupportDepth = 0.006,
		CanvasSize = 256,
		Rows = 128,
		FaceSides = 12,
		RimFraction = 0.9,
		RimShade = 0.87,
		-- SM_ClockBurn/TEX_ClockBurn: colored left half, read clockwise from twelve.
		-- The painted boundary near 340 degrees and sampled colors are adapted to flat GUI fills.
		Sectors = {
			{ Until = 0.75, Color = Color3.fromRGB(236, 148, 63) },
			{ Until = 340 / 360, Color = Color3.fromRGB(211, 77, 41) },
			{ Until = 1, Color = Color3.fromRGB(117, 65, 49) },
		},
		TickAngles = { 180, 225, 270, 315 },
		TickRadius = 0.79,
		TickSize = Vector2.new(0.035, 0.12),
		TickColor = Color3.fromRGB(109, 59, 40),
		-- Outline of the visible red burn mark on SM_ClockBurn, in face coordinates.
		-- It meets the twelve-o'clock seam; a floating capsule made the final sector look empty.
		MarkOutline = {
			Vector2.new(0.5, 0.119),
			Vector2.new(0.480, 0.109),
			Vector2.new(0.457, 0.103),
			Vector2.new(0.435, 0.107),
			Vector2.new(0.420, 0.119),
			Vector2.new(0.413, 0.137),
			Vector2.new(0.414, 0.156),
			Vector2.new(0.425, 0.176),
			Vector2.new(0.443, 0.196),
			Vector2.new(0.469, 0.216),
			Vector2.new(0.5, 0.234),
		},
		MarkColor = Color3.fromRGB(219, 65, 52),
	},
}
