--!strict
-- Rows of the authored daily report. Late replaces burned orders because this
-- game rejects serving burnt food; prepared includes mixer and freezer dishes.
return {
	Rows = {
		{ Key = "Baked", Label = "Dishes Prepared" },
		{ Key = "Burned", Label = "Pastries Burned" },
		{ Key = "Served", Label = "Customers Served" },
		{ Key = "Perfect", Label = "Perfect Orders" },
		{ Key = "Good", Label = "Good Orders" },
		{ Key = "Late", Label = "Late Orders" },
		{ Key = "Lost", Label = "Missed Orders" },
	},
}
