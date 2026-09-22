--!strict
-- Tutorial tuning and copy. Progress and target selection live outside this data module.

return {
	-- Temporary rollout switch; disabling does not complete or reset saved progress.
	Enabled = false,
	Version = 1,
	RecommendedRecipe = "bread",
	FirstGuestType = "regular",
	FirstBakeGrace = 60,
	HintDelay = 12,
	OrderPreviewSeconds = 2.5,
	SuccessSeconds = 4,
	Focus = {
		Thickness = 999999,
		GuiTransparency = 0.45,
		WorldTransparency = 0.65,
		Padding = 12,
		Corner = 14,
		DisplayOrder = 50,
		Cursor = {
			MinSize = 48,
			MaxSize = 80,
			ViewportScale = 0.11,
			-- Fingertip in the authored hand image, relative to its square canvas.
			Tip = Vector2.new(0.30, 0.08),
			TargetInset = 6,
		},
	},
	Stages = { Cook = 1, Serve = 2, Clean = 3, Completed = 3, Skipped = 3 },
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
			id = "Upgrades",
			title = "Upgrades",
			text = "Select an upgrade to see what changes and its price. Buy only when you want that improvement; the tutorial never requires a purchase.",
		},
		{
			id = "NextDay",
			title = "Tomorrow's menu",
			text = "After closing, choose 3–5 available recipes. Next Day saves this menu and starts a new preparation period with no timer.",
		},
	},
}
