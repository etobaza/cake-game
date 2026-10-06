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

	-- A world target in another room points at the doorway first (Shared/UI/HintRoute).
	Route = {
		-- Room name -> folder (from a bakery) whose parts are that room's walkable floor. A point
		-- straight above one of them is in that room; a point above none is Outside.
		Floors = {
			Cafe = { "1ndFloor", "Cafe", "WoodStructure" },
			Kitchen = { "1ndFloor", "Kitchen", "Up/Ground" },
			Garden = { "1ndFloor", "Garden", "Ground" },
		} :: { [string]: { string } },
		Outside = "Outside",
		-- Doorways are models with this lowercased name under DoorRoot, as in Configs/Collision.
		DoorRoot = { "1ndFloor" },
		DoorName = "door",
		-- How far either side of a doorway its two rooms are sampled.
		SideDistance = 6,
		-- Leaves of one doorway (the double front door) closer than this share one waypoint.
		MergeDistance = 8,
		-- Height of the waypoint above the doorway's bottom.
		AimHeight = 3,
		-- A point is classified by a ray cast down from ProbeLift above it, ProbeDepth long.
		ProbeLift = 1,
		ProbeDepth = 24,
		-- Doorways are re-read this often: streaming may load a bakery's floors after the first read.
		RefreshSeconds = 3,
	},
	Accent = Color3.fromRGB(255, 223, 141),
}
