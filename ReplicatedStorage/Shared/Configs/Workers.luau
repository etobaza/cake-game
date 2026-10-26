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
	-- The line under the name saying what the worker does. Short: the tag's width caps its size.
	Role: string,
	-- Where the worker waits between jobs, on the template floor, and the point it turns to face
	-- there (both workers look down the café towards the entrance).
	Idle: Vector3,
	Face: Vector3,
	-- Generated avatar variant, so the same worker always looks the same.
	Variant: number,
	-- Optional accessory models in Shared/MonetizationAssets welded to the head or hand.
	Hat: string?,
	Tool: string?,
	-- Rigid catalog accessories (Shared/MonetizationAssets) worn over the classic clothing.
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
		Role = "Serves & clears tables",
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
		Role = "Cleans spills & tables",
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

	-- The name tag over each worker: bare text with a thick dark outline, sized in studs so it shrinks
	-- with distance like the body, floating Gap studs over the top of the hat. Paid workers' text runs
	-- a holographic gradient over a soft glow of the same colours; WorkerTagHandler (client) animates
	-- every UIGradient named HoloName under the Workers folder.
	Tag = {
		Size = Vector2.new(4.4, 1.6),
		-- The name's share of the tag's height; the role line takes the rest.
		NameShare = 0.6,
		-- The role line is a caption: plain white text on a dark see-through pill, so it reads as
		-- secondary to the name on any wall. Chip width and height are shares of the tag.
		RoleText = Color3.fromRGB(255, 255, 255),
		RoleChip = Color3.fromRGB(30, 18, 40),
		RoleChipTransparency = 0.35,
		RoleChipSize = Vector2.new(0.9, 0.36),
		Gap = 0.25,
		MaxDistance = 60,
		Text = Color3.fromRGB(255, 255, 255),
		Outline = Color3.fromRGB(38, 20, 44),
		-- Outline thickness as a share of the label's height (UIStroke ScaledSize).
		OutlineScale = 0.12,
		Glow = "rbxassetid://115581071626835",
		-- Glow size as a share of the tag, and how see-through it is (pastel on a light wall needs 0).
		GlowSize = Vector2.new(1.3, 2.6),
		GlowTransparency = 0,
		HoloName = "Holo",
		Holo = {
			-- Hue cycles per second, the share of the hue wheel across the text, and the pastel tone.
			Speed = 0.25,
			Span = 0.55,
			Saturation = 0.5,
			Value = 1,
			Keypoints = 8,
			-- The glow trails the text's colours by this share of a cycle and is a little deeper.
			GlowLag = 0.15,
			GlowSaturation = 0.7,
		},
	},
	-- Paid workers stand in a soft pool of golden light on the floor with a few star sparkles rising
	-- from it. Both textures are the group's own, from the authored Assets.VFX effects (Happy's glow
	-- and Cleaning's star), so they load in every place of the experience.
	Aura = {
		Pool = "rbxassetid://115581071626835",
		PoolSize = 4.6,
		-- Studs over the feet.
		PoolLift = 0.2,
		Sparkle = "rbxassetid://17062454177",
		Color = Color3.fromRGB(255, 236, 150),
	},
	FolderName = "Workers",
	WalkSpeed = 10,
}

--[[ Handling ]]--
--- The holographic tag colours at `phase` (hue cycles, any number): pastel hues spread across the
--- tag, so moving the phase slides the rainbow along the text without a seam.
function Workers.HoloColors(phase: number, saturation: number): ColorSequence
	local holo = Workers.Tag.Holo
	-- A ColorSequence needs a keypoint at each end.
	local count = math.max(holo.Keypoints, 2)
	local points = {}
	for index = 0, count - 1 do
		local at = index / (count - 1)
		local hue = (phase + at * holo.Span) % 1
		points[index + 1] = ColorSequenceKeypoint.new(at, Color3.fromHSV(hue, saturation, holo.Value))
	end
	return ColorSequence.new(points)
end

return Workers
