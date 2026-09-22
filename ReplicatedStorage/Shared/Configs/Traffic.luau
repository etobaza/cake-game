--!strict
-- Decorative traffic follows the authored road; the server supplies a shared clock origin.
-- World paths are child names below the world package root (Workspace.World).
return {
	Enabled = true,
	StateName = "TrafficState",
	VisualName = "TrafficVisuals",
	RoadPath = { "Environment", "Road", "road" },
	VehiclesFolder = "Vehicles",
	Speed = 44,
	SpeedVariation = 0.12,
	HeadwaySeconds = 1.2,
	MaxActiveVehicles = 7,
	StartDistance = 110,
	LaneWidthFraction = 0.25,
	EndInset = 32,
	GroundClearance = 0.03,
	Reverse = true,
	Acceleration = 8,
	Braking = 14,
	QueueGap = 8,
	SimulationStep = 1 / 30,
	InterpolationDelay = 0.18,
	MotionAttribute = "TrafficMotion",
	Signals = {
		Path = { "Environment", "Streetlight" },
		HeadName = "Streetlight.001",
		LampTag = "CakeTrafficLamp",
		GreenSeconds = 18,
		YellowSeconds = 3,
		RedSeconds = 12,
		StopBeforeHead = 6,
		StopBuffer = 2,
		OffColor = Color3.fromRGB(40, 38, 34),
		Colors = {
			Red = Color3.fromRGB(255, 48, 38),
			Yellow = Color3.fromRGB(255, 196, 25),
			Green = Color3.fromRGB(60, 255, 95),
		},
	},
	-- The imported SUV, sedan and truck meshes face local +X.
	MeshRotation = CFrame.Angles(0, math.pi / 2, 0),
}
