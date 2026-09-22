--!strict
-- Authored garden rigs and subtle foliage motion; gameplay parts stay in their server pose.
return {
	Tag = "CakeAmbientModel",
	KindAttribute = "AmbientKind",
	CenterAttribute = "AmbientCenter", -- Bee orbit, shared plant pivot, or paired animal skins' phase origin.
	MaxDistance = 170,
	BeeOrbitSpeed = 0.65,
	BeeBob = 0.32,
	BeeBank = math.rad(8),
	PlantAngle = math.rad(0.7),
	PlantSpeed = 1.3,
	ClipSpeeds = { Bee = 3, Cow = 0.65, Chicken = 0.85 },
	MeshKinds = {
		["112008677171490"] = "Bee",
		["137228167834061"] = "Cow",
		["110709913540319"] = "Chicken",
	} :: { [string]: string },
}
