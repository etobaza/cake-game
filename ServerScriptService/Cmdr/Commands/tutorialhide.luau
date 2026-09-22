--!strict
-- Shared Cmdr metadata; authorization and profile access stay on the server.

return {
	Name = "tutorialhide",
	Aliases = { "tuthide" },
	Description = "Collapse the tutorial guidance without skipping it.",
	Group = "TutorialDebug",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player; defaults to yourself.",
			Optional = true,
		},
	},
}
