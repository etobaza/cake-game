--!strict
-- Player animation roles. Published priorities/loop flags are overridden here deliberately.
-- Locomotion/work clips use the player Animator; TrayHandler samples the arm-only carry overlay.

export type Clip = {
	Id: string,
	Priority: Enum.AnimationPriority,
	Looped: boolean,
	ReferenceSpeed: number?,
	-- A local authored joint overlay; do not load this full-body asset as an AnimationTrack.
	PoseSequence: string?,
	Joints: { [string]: string }?,
	Hand: string?,
	-- A work track keeps its Animator playback; this arm sample bridges directly from its hold.
	TransitionSequence: string?,
	TransitionHold: string?,
}

export type Action = { ToolId: string?, CancelOnMove: boolean }

local CharacterAnimations = {
	RigType = Enum.HumanoidRigType.R15,
	RunningAttribute = "CakeRunning",
	FadeTime = 0.18,
	MovingThreshold = 0.5,
	MinPlaybackSpeed = 0.15,
	MaxPlaybackSpeed = 2,
	-- Hold clips contain full-body keys; only their configured arms overlay locomotion.
	CarryEnabled = true,
	PoseAssetTimeout = 10,
	Actions = {
		Sweep = { ToolId = "broom", CancelOnMove = true },
		Cleaning = { CancelOnMove = true },
		PetCat = { CancelOnMove = true },
	} :: { [string]: Action },
	GroundStates = {
		[Enum.HumanoidStateType.Running] = true,
		[Enum.HumanoidStateType.RunningNoPhysics] = true,
		[Enum.HumanoidStateType.Landed] = true,
	},
	Clips = {
		Idle = { Id = "rbxassetid://131634221877151", Priority = Enum.AnimationPriority.Idle, Looped = true },
		Walk = {
			Id = "rbxassetid://93168013685115",
			Priority = Enum.AnimationPriority.Movement,
			Looped = true,
			ReferenceSpeed = 16,
		},
		Run = {
			Id = "rbxassetid://73570091079377",
			Priority = Enum.AnimationPriority.Movement,
			Looped = true,
			ReferenceSpeed = 24,
		},
		Broomhold = {
			Id = "rbxassetid://140534118876421",
			Priority = Enum.AnimationPriority.Action,
			Looped = true,
			PoseSequence = "Broomhold_RightArm",
			Hand = "Right",
			Joints = { RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow", RightHand = "RightWrist" },
		},
		Carry = {
			Id = "rbxassetid://85167873003202",
			Priority = Enum.AnimationPriority.Action,
			Looped = true,
			PoseSequence = "Carry_Arms",
			Hand = "Left",
			Joints = {
				LeftUpperArm = "LeftShoulder",
				LeftLowerArm = "LeftElbow",
				LeftHand = "LeftWrist",
				RightUpperArm = "RightShoulder",
				RightLowerArm = "RightElbow",
				RightHand = "RightWrist",
			},
		},
		LeikaHold = {
			Id = "rbxassetid://133683032090339",
			Priority = Enum.AnimationPriority.Action,
			Looped = true,
			PoseSequence = "LeikaHold_Arms",
			Hand = "Right",
			Joints = {
				LeftUpperArm = "LeftShoulder",
				LeftLowerArm = "LeftElbow",
				LeftHand = "LeftWrist",
				RightUpperArm = "RightShoulder",
				RightLowerArm = "RightElbow",
				RightHand = "RightWrist",
			},
		},
		Trayfoodhold = {
			Id = "rbxassetid://99587872959291",
			Priority = Enum.AnimationPriority.Action,
			Looped = true,
			PoseSequence = "Trayfoodhold_RightArm",
			Hand = "Right",
			Joints = { RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow", RightHand = "RightWrist" },
		},
		Interact = { Id = "rbxassetid://126842495915494", Priority = Enum.AnimationPriority.Action2, Looped = true },
		Cleaning = { Id = "rbxassetid://121783147086381", Priority = Enum.AnimationPriority.Action2, Looped = false },
		PetCat = { Id = "rbxassetid://126842495915494", Priority = Enum.AnimationPriority.Action2, Looped = false },
		Sweep = {
			Id = "rbxassetid://93354094794576",
			Priority = Enum.AnimationPriority.Action2,
			Looped = false,
			TransitionSequence = "Sweep_RightArm",
			TransitionHold = "Broomhold",
		},
	} :: { [string]: Clip },
}

return CharacterAnimations
