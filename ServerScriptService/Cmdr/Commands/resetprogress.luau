--!strict
-- Shared Cmdr metadata; the reset is requested and applied only by the server.

return {
	Name = "resetprogress",
	Description = "Reset gameplay progress to new-player defaults on rejoin. Disconnects the player; paid ownership survives.",
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
