--!strict
-- Shared Cmdr metadata; authorization and profile access stay on the server.

return {
	Name = "unlockallupgrades",
	Aliases = { "maxupgrades" },
	Description = "Grant every cafe, kitchen and garden upgrade at maximum level for free.",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player; defaults to yourself. Grants persist in their profile.",
			Optional = true,
		},
	},
}
