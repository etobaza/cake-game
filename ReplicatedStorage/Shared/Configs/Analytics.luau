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

	-- Script errors reported by ErrorReportHandler: one custom event per error with the realm
	-- ("Server" or "Client") in the first field and the erroring script's name in the second.
	-- Messages and line numbers stay out of the event; they would explode field cardinality.
	Errors = {
		Event = "ScriptError",
		-- The same script reports at most once per window: per server for server errors, per player
		-- for client errors.
		DedupeSeconds = 300,
		-- Client reports a player may send per minute, whatever the script.
		ClientPerMinute = 6,
		MaxKeyLength = 48,
		-- No script could be named, or a client named one the server does not ship to clients.
		UnknownKey = "Unknown",
		OtherKey = "Other",
	},
}
