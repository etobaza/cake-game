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
	OrderPreviewSeconds = 2.5,
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
			text = "Take the broom, approach a puddle and use Clean. Return the broom to free your hand before cooking.",
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
