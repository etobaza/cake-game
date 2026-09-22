--!strict
-- Shared Cmdr metadata; authorization and profile access stay on the server.

return {
	Name = "tutorialcomplete",
	Aliases = { "tutcomplete" },
	Description = "Mark the active introduction completed and release tutorial protection.",
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
