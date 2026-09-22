--!strict
-- Shared Cmdr metadata; the reset is requested and applied only by the server.

return {
	Name = "resetprogress",
	Description = "Reset gameplay progress on rejoin and start with money for every upgrade. Disconnects the player.",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player; defaults to yourself. Paid ownership is preserved.",
			Optional = true,
		},
	},
}
