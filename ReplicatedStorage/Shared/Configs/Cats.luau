--!strict
-- Lemon Cake build 6596857: BP_CatCafe, BP_Cat and BP_Client. See ARCHITECTURE.md.
local Cats = {
	Tag = "CakeCafeCat",
	UpgradeId = "cafe_catcafe",
	FolderName = "CafeCats",
	TemplatesFolder = "Cats",
	-- SK_Cat length * BP_Cat scale / SM_CatTree height * BP_CatCafe tree scale.
	-- SpawnCats explicitly uses unit actor scale, ignoring the location marker's 0.5 X scale.
	LengthToTreeHeight = (171.24664306640625 * 0.85) / (173.48988342285156 * 1.075),
	InteractDistance = 8,
	PetSeconds = 1,
	PetCooldown = 1.5,
	AdoptSeconds = 1.25,
	AdoptTimeout = 25,
	AdoptReward = 7.5,
	AdoptChance = 0.1,
	PetAdoptBonus = 0.05,
	MaxAdoptChance = 0.3,
	AnimationFade = 0.2,
	AnimationLoadTimeout = 10,
	Animations = {
		Idle = "rbxassetid://126389676712511",
		Sit = "rbxassetid://135343672107449",
		Lay = "rbxassetid://93842005172996",
		Walk = "rbxassetid://127796826962136",
	} :: { [string]: string },
	-- The supplied set has no dedicated playing, drinking or scratching clips.
	ClipByPose = { Idle = "Idle", Play = "Idle", Sit = "Sit", Lay = "Lay", Walk = "Walk" } :: { [string]: string },
	Counts = { { Min = 1, Max = 2 }, { Min = 2, Max = 4 } },
	-- Each slot uses the authored habitat's local space; Y is measured from its base.
	Slots = {
		{ Id = "Top", Level = 1, Habitat = "CatHabitatOne", Pose = "Rest", Offset = Vector3.new(0, 4.956, 0), Yaw = 0 },
		{
			Id = "Tunnel",
			Level = 1,
			Habitat = "CatHabitatOne",
			Pose = "Lay",
			Offset = Vector3.new(-0.65, 1.8, 0),
			Yaw = 0,
		},
		{ Id = "Play", Level = 1, Habitat = "CatHabitatOne", Pose = "Play", Offset = Vector3.new(-3.3, 0, 0), Yaw = 0 },
		{ Id = "Bed", Level = 2, Habitat = "CatHabitatTwo", Pose = "Rest", Offset = Vector3.new(0, 0.7, 0), Yaw = 0 },
		{
			Id = "Scratch",
			Level = 2,
			Habitat = "CatHabitatThree",
			Pose = "Scratch",
			Offset = Vector3.new(0, 0, 1.4),
			Yaw = -90,
		},
	},
}
return Cats
