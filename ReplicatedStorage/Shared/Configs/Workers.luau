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
	-- Where the worker waits between jobs, on the template floor, and the point it turns to face
	-- there (both workers look down the café towards the entrance).
	Idle: Vector3,
	Face: Vector3,
	-- Generated avatar variant, so the same worker always looks the same.
	Variant: number,
	-- Optional accessory models in ReplicatedStorage.MonetizationAssets welded to the head or hand.
	Hat: string?,
	Tool: string?,
	-- Rigid catalog accessories (MonetizationAssets) worn over the classic clothing.
	Extras: { string }?,
	-- Classic catalog clothing templates (the image ids behind the catalog Shirt and Pants items).
	Shirt: string,
	Pants: string,
	-- Body colours under the clothing, shown if a template fails to load.
	Torso: Color3,
	Legs: Color3,
}

--[[ Tables ]]--
local Workers = {
	Helper = {
		Label = "Helper",
		Idle = Vector3.new(241, 1.16, -345.5),
		Face = Vector3.new(221, 1.16, -345.5),
		Variant = 7,
		Hat = "HelperHat",
		-- Catalog 80659885550649 "Apron" (rhulk) and 9058381905 "Baker's Rolling Pin" (ILuvVideoGamez).
		Extras = { "HelperApron", "HelperRollingPin" },
		-- Catalog 7991805601 "Chef" and 7991805992 "Chef" by PD Clothing Brand.
		Shirt = "rbxassetid://7991805591",
		Pants = "rbxassetid://7991805977",
		Torso = Color3.fromRGB(245, 245, 240),
		Legs = Color3.fromRGB(60, 60, 70),
	} :: Worker,
	Cleaner = {
		Label = "Cleaner",
		-- Clear of the potted plant beside the kitchen wall, so it does not stand face into it.
		Idle = Vector3.new(236, 1.16, -300),
		Face = Vector3.new(216, 1.16, -300),
		Variant = 12,
		-- Catalog 14587283486 "Ellis Mechanic Cap" (cool stuff and things).
		Hat = "CleanerCap",
		Tool = "CleanerMop",
		-- Catalog 76412086465786 "Yellow Neckerchief" (Wild West UGC) and 74498838771791
		-- "BLF ID Card - Janitor" (Blue Line Factory).
		Extras = { "CleanerScarf", "CleanerBadge" },
		-- Catalog 15054768904 "Blue Jumpsuit +" and 15054953636 "Blue Jumpsuit -" by Soil-18 Supply Reserves.
		Shirt = "rbxassetid://15054768882",
		Pants = "rbxassetid://15054953592",
		Torso = Color3.fromRGB(70, 170, 175),
		Legs = Color3.fromRGB(45, 70, 110),
	} :: Worker,

	-- The Helper pass unlocks the assistant (a Stat pass on AssistantSlots) and divides its job
	-- interval by this. A bought assistant upgrade gets the same body without the speed or the aura.
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
	-- Clips that swing the tool: while they play the back-worn `Tool` accessory is swapped for its
	-- `<Tool>Held` template in the right hand (CleanerMop and CleanerMopHeld).
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
