--!strict
-- Shared presentation defaults. Callers own when a hint appears and what it means.

export type FingerPhase = "Rest" | "Press" | "Hold" | "Release"
type PhaseDefinition = { Fraction: number, Pose: number, Next: FingerPhase }

return {
	DisplayOrder = 55,
	Priority = 0,
	TutorialPriority = 20,
	DebugPriority = 100,
	TutorialWorldOffset = Vector3.new(0, 0.6, 0),

	Debug = {
		GuiPath = "Time",
		PropId = "mixer_1",
		WorldOffset = Vector3.new(0, 1, 0),
		DemoRadius = 14,
		DemoHeight = 2,
		DemoAngularSpeed = 0.35,
	},

	Images = {
		Straight = "rbxassetid://78646053977990",
		Bent = "rbxassetid://136686601060102",
	},

	FingerTip = Vector2.new(0.4, 0.18),
	FingerSize = 88,
	MinFingerSize = 48,
	MinScaledFingerSize = 24,
	MaxFingerViewportFraction = 0.25,
	ReferenceHeight = 900,
	GuiMaxRotation = 65,
	RotationSpeed = 10,

	-- Clamp frame time so a stalled frame does not skip the entire press animation.
	MaxAnimationDelta = 0.1,
	FingerPeriod = 2.8,
	MinFingerPeriod = 0.4,
	-- Fractions of FingerPeriod: rest, press, hold, release.
	FingerPhases = {
		Rest = { Fraction = 0.30, Pose = 0, Next = "Press" },
		Press = { Fraction = 0.22, Pose = 1, Next = "Hold" },
		Hold = { Fraction = 0.12, Pose = 1, Next = "Release" },
		Release = { Fraction = 0.36, Pose = 0, Next = "Rest" },
	} :: { [FingerPhase]: PhaseDefinition },

	FocusDuration = 0.45,
	Padding = 8,
	CornerRadius = 12,
	ShadeColor = Color3.fromRGB(21, 16, 30),
	ShadeTransparency = 0.48,
	EdgePadding = 14,

	OcclusionInterval = 0.2,
	OcclusionMinRayLength = 0.1,
	OcclusionMaxHits = 4,
	OcclusionTargetRadius = 2,
	OcclusionTransparency = 0.8,

	Beam = {
		Template = "ArrowBeam",
		PlayerOffset = Vector3.new(0, -2, 0),
		MinDistance = 2,
		RetryInterval = 1,
		MinTextureLength = 0.1,
		MinTextureSpacing = 0.1,
	},
	Accent = Color3.fromRGB(255, 223, 141),
}
