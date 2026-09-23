--!strict
return {
	Name = "hinttest",
	Aliases = { "hint" },
	Description = "Preview reusable hints: gui [HUD path], world [owned prop ID], demo, or hide. Preview only; no progress changes.",
	Group = "TutorialDebug",
	Args = {
		{ Type = "string", Name = "mode", Description = "gui, world, demo, or hide", Optional = true },
		{
			Type = "string",
			Name = "target",
			Description = "HUD-relative GUI path or owned prop ID; '-' selects the default.",
			Optional = true,
		},
		{
			Type = "number",
			Name = "seconds",
			Description = "Preview duration, 1–300 seconds (default 30).",
			Optional = true,
		},
		{
			Type = "string",
			Name = "rotation",
			Description = "auto or an angle in degrees, such as 45, 60, -60.",
			Optional = true,
		},
	},
}
