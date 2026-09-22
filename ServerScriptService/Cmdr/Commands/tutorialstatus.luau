--!strict
-- Shared Cmdr metadata; authorization and profile access stay on the server.

return {
	Name = "tutorialstatus",
	Aliases = { "tutstatus" },
	Description = "Show tutorial status, stage, target, learned actions and lessons.",
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
