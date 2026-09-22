--!strict
-- Shared Cmdr metadata; the server derives the budget from the player's remaining upgrades.

return {
	Name = "upgrademoney",
	Description = "Top up coins to afford every remaining upgrade level without resetting progress.",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player; defaults to yourself.",
			Optional = true,
		},
	},
}
