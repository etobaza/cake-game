--!strict
-- Shared Cmdr metadata; authorization and profile access stay on the server.

return {
	Name = "tutorialskip",
	Aliases = { "tutskip" },
	Description = "Skip the active introduction and release tutorial protection.",
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
