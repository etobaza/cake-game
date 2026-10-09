--!strict
-- Tutorial tuning and copy. Progress and target selection live outside this data module.

return {
	-- Disabling presentation and protection never resets saved progress.
	Enabled = true,
	IntroCleanup = true,
	Version = 1,
	RecommendedRecipe = "bread",
	FirstGuestType = "regular",
	FirstBakeGrace = 30,
	-- Where the introduction's spill lies, in the kitchen floor's local space (studs from its
	-- centre): beside the walk from the broom rack to the mixer.
	SpillOffset = Vector3.new(-1.8, 0, 10.3),
	-- The first order card stays in focus until the player taps it; this is only the fallback for
	-- players who cannot tap it (gamepad).
	OrderPreviewSeconds = 20,
	-- Extra room around the order card's spotlight, in pixels.
	OrderFocusPadding = 22,
	SuccessSeconds = 4,
	RefreshInterval = 0.15,
	GoalSettleSeconds = 0.25,
	ReminderSeconds = 18,
	GuestHighlight = {
		Color = Color3.fromRGB(255, 221, 128),
		FillTransparency = 0.8,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	},
	-- The guide's speech bubble (Shared/UI/Tutorial/Dialog): a cat mentor at the bottom of the
	-- screen whose bubble stays up for as long as its step is active. Sizes are reference pixels at
	-- `ReferenceHeight`; one UIScale follows the viewport height.
	Dialog = {
		-- Above the hint overlay's dim (55), so the step text is never darkened.
		DisplayOrder = 56,
		ReferenceHeight = 900,
		MinScale = 0.62,
		MaxScale = 1.35,
		Width = 600,
		MinWidth = 320,
		-- Share of the viewport width the whole dialog may use.
		WidthRatio = 0.62,
		-- Gap above the hotbar, and the bottom margin when no hotbar is found.
		HotbarGap = 12,
		BottomMargin = 110,
		-- Gap below the clock when the dialog moves to the top to clear its own target.
		TopGap = 14,
		TopFallback = 130,
		SpeakerName = "Mochi",
		Portrait = {
			-- Nana Crumble, the friendly ghost of the bakery's old owner (modelled on Lemon Cake's
			-- ghost mentor, with original art). Uploaded mood images; while Neutral is empty the
			-- authored cat model below speaks instead.
			Name = "Nana Crumble",
			-- funset_tutorial_nana_<mood> (group 712136202), generated with Codex in the HUD icon style
			-- and keyed to alpha. Images owned by a personal account do not load in this experience.
			Images = {
				Neutral = "rbxassetid://91114958777567",
				Happy = "rbxassetid://91604123612355",
				Surprised = "rbxassetid://133640805449280",
				Spooked = "rbxassetid://91917403951074",
				Sad = "rbxassetid://124430413895917",
			} :: { [string]: string },
			Moods = {
				Default = "Neutral",
				Urgent = "Spooked",
				Recovery = "Surprised",
				-- Shown with the Done! stamp.
				Done = "Happy",
				ById = {
					completed = "Happy",
					eating = "Happy",
					guest_arriving = "Happy",
					order_card = "Surprised",
					intro_preparing = "Neutral",
					close_for_oven = "Spooked",
				} :: { [string]: string },
				ByPrefix = {
					intro_sweep_ = "Spooked",
					discard_ = "Sad",
				} :: { [string]: string },
			},
			-- The mood images' square size; her toque rises above the bubble.
			ImageSize = 180,
			-- Gap from the image's right edge to the copy; negative because the art has a
			-- transparent margin on that side.
			ImageGap = -18,
			-- A slow bob and sway, in reference pixels and degrees, around a lean toward the
			-- bubble (Lemon Cake tilts its speaker portrait 2.5 degrees).
			Float = { Period = 2.8, Pixels = 3, Sway = 1.5 },
			Tilt = 2.5,
			Template = "Cats",
			Size = 132,
			-- The bubble starts this far into the portrait, so the cat leans over its edge and
			-- needs no speech tail.
			BubbleStart = 0.74,
			-- Camera on the cat's head bone: turned this far off its face, raised and pulled back
			-- in studs, aimed a little below the head so the chest shows too.
			FocusBone = "Head",
			Yaw = 32,
			Lift = 0.8,
			Distance = 4.8,
			FocusDrop = 0.35,
			FieldOfView = 30,
			BreathPeriod = 2.6,
			BreathScale = 0.02,
			HopPixels = 4,
			HopSeconds = 0.12,
		},
		TitleSize = 26,
		HintSize = 18,
		-- The bubble shows only the step title; true adds the goal's longer hint below it.
		ShowHint = false,
		LineGap = 4,
		Padding = Vector2.new(20, 14),
		-- Space between the portrait's right edge and the copy.
		PortraitGap = 8,
		MinBubbleHeight = 72,
		Corner = 18,
		Stroke = 3,
		ShadowDrop = 6,
		ShadowTransparency = 0.72,
		PlateHeight = 28,
		PlateTextSize = 17,
		ItemSize = 54,
		ItemGap = 12,
		ButtonHeight = 34,
		ButtonTextSize = 17,
		Colors = {
			Ink = Color3.fromRGB(74, 40, 30),
			Hint = Color3.fromRGB(122, 82, 64),
			FillTop = Color3.fromRGB(255, 252, 244),
			FillBottom = Color3.fromRGB(253, 234, 195),
			Plate = Color3.fromRGB(240, 128, 40),
			Emphasis = Color3.fromRGB(232, 118, 0),
			Done = Color3.fromRGB(64, 170, 84),
			Button = Color3.fromRGB(64, 170, 84),
			Shadow = Color3.fromRGB(0, 0, 0),
		},
		-- Typewriter: seconds per character and extra pauses after sentence and clause marks.
		CharSeconds = 0.022,
		SentencePause = 0.18,
		CommaPause = 0.07,
		-- The typing voice, BattlesOfEmpires style: one quiet sound restarted on each letter.
		-- Silent while Id is empty (the old pop on every fourth letter was too loud). The id is the
		-- public "UnderTale - sans.(Text)" audio that BattlesOfEmpires' SFX.Dialogue.TextSay uses.
		Voice = { Id = "rbxassetid://5416485881", Volume = 0.3, Pitch = { Min = 0.95, Max = 1.1 } },
		AppearSeconds = 0.32,
		-- A new line makes the bubble swell and hop (Lemon Cake's AN_DialogueChange).
		Boing = { Seconds = 0.35, Scale = 1.03, Lift = 10 },
		ExitSeconds = 0.18,
		MoveSmoothing = 0.08,
		-- A goal-less moment shorter than this (a step handing over) keeps the bubble up.
		HideGrace = 0.4,
		-- A step stays readable at least this long before the next one replaces it, and a
		-- finished step shows its Done! stamp this long first.
		MinShowSeconds = 1.4,
		DoneSeconds = 0.75,
		DoneText = "Done!",
		-- Read-only steps the player can acknowledge from the bubble itself.
		Acknowledge = { order_card = "Got it" } :: { [string]: string },
	},
	Stages = { Sweep = 1, Cook = 2, Serve = 3, Clean = 4, Completed = 4, Skipped = 4 },
	-- After the introduction: help a player who stopped making progress or repeats a failed action.
	-- Each situation first explains the cause in a short toast; a pointer follows only if the player
	-- still has not acted, so the step is understood rather than clicked through.
	Coach = {
		Enabled = true,
		-- Seconds without progress before the explanation (Nudge) and the pointer (Point).
		-- Cooldown = true makes the nudge wait for `Cooldown` seconds after the previous one.
		Delays = {
			Stuck = { Nudge = 30, Point = 50, Cooldown = true },
			Urgent = { Nudge = 8, Point = 15, Cooldown = false },
			Prep = { Nudge = 60, Point = 90, Cooldown = true },
			Feature = { Nudge = 0, Point = 8, Cooldown = false },
			-- Evening plan after the first one: report, 3 to 5 recipes, Next Day.
			Summary = { Nudge = 45, Point = 70, Cooldown = true },
			-- Nothing is demanded: quiet moments, spills, used places without new guests.
			Idle = { Nudge = 45, Point = 70, Cooldown = true },
			-- A wrong dish in hand while guests wait, until the player has binned one once.
			Waste = { Nudge = 4, Point = 10, Cooldown = false },
		},
		Cooldown = 60,
		-- Pointers per step kind and session; afterwards that step only gets the explanation.
		PointsPerStep = 2,
		-- Fresh bakers forget the routine most: the first days wait less and point more often.
		-- `Scale` multiplies every delay except Feature; the lowest MaxDay that is >= Cloud.Day wins,
		-- later days use the plain values above.
		Experience = {
			{ MaxDay = 3, Scale = 0.5, Cooldown = 25, PointsPerStep = 5 },
			{ MaxDay = 6, Scale = 0.75, Cooldown = 40, PointsPerStep = 3 },
		},
		-- A waiting guest with less patience than this left makes their dish urgent.
		HurrySeconds = 20,
		-- Repeated refusals in this window skip the wait and show the pointer at once.
		FailureCount = 2,
		FailureWindow = 30,
		BoostSeconds = 20,
		-- Refusal codes that signal a misunderstanding rather than a busy station or distance.
		Confusion = {
			bake_before_serving = true,
			wrong_dish = true,
			nothing_to_serve = true,
			nothing_to_place = true,
			need_firewood = true,
			select_recipe = true,
			ingredient_not_needed = true,
			ingredient_complete = true,
			missing_ingredients = true,
			nothing_to_load = true,
			need_frozen_mix = true,
			wrong_frozen_mix = true,
			wrong_station = true,
			not_ready = true,
			need_broom = true,
			need_watering_can = true,
			nothing_to_harvest = true,
		} :: { [string]: boolean },
		-- Steps another guide already leads to (the carried-tool return path): explanation only.
		NudgeOnly = { return_tool = true } :: { [string]: boolean },
		-- One between-days feature introduction stays in the toast this long before the next.
		IntroSeconds = 6,
	},
	-- Bought upgrades the player has to use actively. A feature owned for a whole shift without
	-- one use becomes due: the evening, the next preparation and the next shift explain it once.
	-- If another whole shift passes unused, the guide retires for good.
	Features = {
		{
			id = "display",
			upgrade = "cafe_display",
			prefix = "display",
			actions = { Place = true },
			intro = "Counter guests buy dishes from the display",
		},
		{
			id = "window",
			upgrade = "cafe_window",
			prefix = "window",
			actions = { Place = true },
			intro = "Pass dishes through the kitchen window",
		},
		{
			id = "oven2",
			upgrade = "kitchen_oven",
			prefix = "oven",
			minIndex = 2,
			actions = { Load = true },
			intro = "Two ovens bake two batches at once",
		},
		{
			id = "freezer",
			upgrade = "kitchen_freezer",
			prefix = "freezer",
			actions = { Load = true },
			station = "Freezer",
			intro = "Frozen mixes chill in the freezer",
		},
		{
			id = "coffee",
			upgrade = "cafe_coffee",
			prefix = "coffee",
			station = "Coffee",
			intro = "Make coffee at the coffee machine",
		},
		{
			id = "assistant",
			upgrade = "cafe_assistant",
			-- Used once the evening plan gives the assistant any job.
			task = true,
			intro = "Your assistant works the job you chose",
		},
	} :: {
		{
			id: string,
			upgrade: string,
			prefix: string?,
			minIndex: number?,
			actions: { [string]: boolean }?,
			station: string?,
			task: boolean?,
			intro: string,
		}
	},
	Topics = {
		{
			id = "Cooking",
			title = "Cooking",
			text = "Choose a recipe at the mixer. Carry one ingredient at a time, mix, then move the dough to its next station. Firewood burns over time, even in an empty oven. Add a log whenever needed; baking and burning pause without fire. Collect baked food before it burns.",
		},
		{
			id = "Serving",
			title = "Guests & tables",
			text = "Open with the clock. Take an order at a guest's table, carry their dish to that seat, then clean the used place after they finish eating.",
		},
		{
			id = "Display",
			title = "The display",
			text = "Put a finished dish on an empty display spot. Counter guests buy stocked dishes themselves; you can also take food back to serve a table.",
		},
		{
			id = "Floor",
			title = "Spills",
			text = "Take the broom, approach a puddle and press Sweep. Return the broom to free your hand before cooking.",
		},
		{
			id = "Garden",
			title = "The garden",
			text = "Water plants with the can; brush animals with empty hands. Return tools before harvesting. Each harvest gives one ingredient. Cared-for sources keep producing.",
		},
		{
			id = "Cart",
			title = "Garden delivery",
			text = "Load harvested produce into the garden cart. It travels to the kitchen and returns by itself. Collect deliveries at the kitchen rail output, one at a time.",
		},
		{
			id = "NextDay",
			title = "Tomorrow's menu",
			text = "After closing, choose 3–5 available recipes. Next Day saves this menu and starts a new preparation period with no timer.",
		},
	},
}
