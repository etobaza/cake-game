--!strict
-- Bakery workers you can see: the Helper (the assistant, shown as a chef) and the Auto-Cleaner.
--
-- AssistantHandler still decides the Helper's jobs; WorkerHandler only gives it a body that walks to
-- each job. The Cleaner's jobs are WorkerHandler's own. Positions are in the template bakery's space
-- (BaseConfig.TemplateName) and mapped into each bakery through BaseHandler:GetTransform.

--[[ Types ]]--
export type Worker = {
	-- Shown over the head and used as the model name.
	Label: string,
	-- Where the worker waits between jobs, on the template floor.
	Idle: Vector3,
	-- Generated avatar variant, so the same worker always looks the same.
	Variant: number,
	-- Optional accessory models in ReplicatedStorage.MonetizationAssets welded to the head or hand.
	Hat: string?,
	Tool: string?,
	-- Shirt (and sleeve) and pants colours, so the outfit reads at a glance.
	Torso: Color3,
	Legs: Color3,
}

--[[ Tables ]]--
local Workers = {
	Helper = {
		Label = "Helper",
		Idle = Vector3.new(241, 1.16, -345.5),
		Variant = 7,
		Hat = "HelperHat",
		Torso = Color3.fromRGB(245, 245, 240),
		Legs = Color3.fromRGB(60, 60, 70),
	} :: Worker,
	Cleaner = {
		Label = "Cleaner",
		Idle = Vector3.new(238.5, 1.16, -302.5),
		Variant = 12,
		Hat = "CleanerCap",
		Tool = "CleanerMop",
		Torso = Color3.fromRGB(70, 170, 175),
		Legs = Color3.fromRGB(45, 70, 110),
	} :: Worker,

	-- The Helper pass unlocks the assistant (a Stat pass on AssistantSlots) and divides its job
	-- interval by this. A bought assistant upgrade gets the same body without the speed or the aura.
	-- White classic shirt template (torso and sleeves to the wrist, hands clear), tinted per worker.
	ShirtTemplate = "rbxassetid://136954613152914",

	HelperPass = "pass_helper",
	HelperSpeedup = 2,
	CleanerPass = "pass_cleaner",
	-- One cleaning job per this many seconds: walk there, then wipe or mop.
	CleanerInterval = 6,
	-- Seconds spent wiping or mopping once there, and the walk's give-up time.
	CleanSeconds = 1.2,
	-- The player's own clips (CharacterAnimations.Clips), looped while the Cleaner works: the broom
	-- sweep on a puddle, the wipe on a table.
	SpillClip = "Sweep",
	TableClip = "Cleaning",
	-- Clips that swing the held tool: it switches from its IdleGrip to its WorkGrip attachment
	-- while they play (the CleanerMop asset carries both).
	WorkGripClips = { Sweep = true } :: { [string]: boolean },
	WalkTimeout = 12,

	-- The open arch between the café and the kitchen, on the template floor. A job on the kitchen
	-- side (template X beyond ArchX) walks through these two points.
	ArchX = 244.4,
	ArchCafe = Vector3.new(240, 1.16, -322.7),
	ArchKitchen = Vector3.new(249, 1.16, -322.7),

	-- Paid workers wear a soft golden aura (sprites uploaded for the limited showcase).
	AuraSparkle = "rbxassetid://76997036595742",
	AuraGlow = "rbxassetid://123558827351128",
	FolderName = "Workers",
	WalkSpeed = 10,
}

return Workers
