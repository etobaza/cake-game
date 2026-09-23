--!strict
-- Shared Cmdr metadata; authorization and profile access stay on the server.

return {
	Name = "tutorialreset",
	Aliases = { "tutreset", "tutorialtest" },
	Description = "Reset tutorial progress and optional lessons, retaining the current kitchen. Restarts guests and pauses the clock during Shift.",
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
