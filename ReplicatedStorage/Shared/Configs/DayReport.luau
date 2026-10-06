--!strict
-- Rows of the authored daily report. Late replaces burned orders because this
-- game rejects serving burnt food; prepared includes mixer and freezer dishes.

--[[ Types ]]--
export type Row = {
	Key: string,
	Label: string,
	-- A row the screen was not drawn with is cloned from this authored row.
	Template: string?,
}

return {
	Rows = {
		{ Key = "Baked", Label = "Dishes Prepared" },
		{ Key = "Burned", Label = "Pastries Burned" },
		{ Key = "Served", Label = "Customers Served" },
		{ Key = "Perfect", Label = "Perfect Orders" },
		{ Key = "Good", Label = "Good Orders" },
		{ Key = "Late", Label = "Late Orders" },
		{ Key = "Lost", Label = "Missed Orders" },
		{ Key = "BestStreak", Label = "Best Streak", Template = "Served" },
	} :: { Row },
}
