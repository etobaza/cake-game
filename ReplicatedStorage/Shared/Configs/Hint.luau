--!strict
-- Shared presentation defaults. Callers own when a hint appears and what it means.
return {
	DisplayOrder = 55,
	Priority = 0,
	TutorialPriority = 20,
	DebugPriority = 100,
	Images = {
		Straight = "rbxassetid://78646053977990",
		Bent = "rbxassetid://136686601060102",
	},
	FingerTip = Vector2.new(0.4, 0.18),
	FingerSize = 88,
	MinFingerSize = 48,
	ReferenceHeight = 900,
	FingerPeriod = 2.8,
	-- Fractions of FingerPeriod: rest, press, hold, release.
	FingerPhases = {
		{ Fraction = 0.30, Pose = 0 },
		{ Fraction = 0.22, Pose = 1 },
		{ Fraction = 0.12, Pose = 1 },
		{ Fraction = 0.36, Pose = 0 },
	},
	FocusDuration = 0.45,
	RotationSpeed = 10,
	Padding = 8,
	CornerRadius = 12,
	ShadeTransparency = 0.48,
	EdgePadding = 14,
	OcclusionInterval = 0.2,
	Beam = {
		Template = "ArrowBeam",
		PlayerOffset = Vector3.new(0, -2, 0),
		MinDistance = 2,
	},
	Accent = Color3.fromRGB(255, 223, 141),
}
