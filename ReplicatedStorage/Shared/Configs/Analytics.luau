--!strict
-- Creator Dashboard analytics owned by the server AnalyticsHandler. Names here become dashboard
-- keys: renaming one starts a new series, so keep them stable once the game is live.

return {
	-- Studio never sends events; set this to print each one through the AnalyticsHandler logger.
	PrintInStudio = false,
	Currency = "Coins",

	-- Recurring funnels. Step order is the funnel order; a run never goes back to an earlier step.
	Funnels = {
		-- One run per in-game day: morning preparation to planning the next day.
		Day = {
			Name = "Day",
			Steps = { "Prep", "Opened", "FirstSale", "Closed", "NextDay" },
		},
		-- One run per purchase prompt; the product id goes in the first custom field.
		Store = {
			Name = "Store",
			Steps = { "Prompted", "Purchased" },
		},
	},

	-- Accepted kitchen actions (TutorialEvents) reported as custom events with value 1.
	ActionEvents = {
		DisposeBurnt = "DishBurnt",
		DisposeDish = "DishWasted",
	} :: { [string]: string },

	-- Custom fields carry this coarse day label instead of the raw day, to keep cardinality low.
	DayBuckets = {
		{ MaxDay = 1, Label = "Day1" },
		{ MaxDay = 3, Label = "Day2-3" },
		{ MaxDay = 7, Label = "Day4-7" },
		{ MaxDay = 14, Label = "Day8-14" },
	},
	LateDayLabel = "Day15+",
}
