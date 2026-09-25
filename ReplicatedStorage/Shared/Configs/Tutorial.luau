--!strict
-- Tutorial tuning and copy. Progress and target selection live outside this data module.

return {
	-- Disabling presentation and protection never resets saved progress.
	Enabled = true,
	IntroCleanup = true,
	Version = 1,
	RecommendedRecipe = "bread",
	FirstGuestType = "regular",
	FirstBakeGrace = 60,
	OrderPreviewSeconds = 2.5,
	SuccessSeconds = 4,
	RefreshInterval = 0.15,
	GoalSettleSeconds = 0.25,
	ReminderSeconds = 18,
	Stages = { Sweep = 1, Cook = 2, Serve = 3, Clean = 4, Completed = 4, Skipped = 4 },
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
