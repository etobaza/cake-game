--!strict
-- Shared Cmdr metadata; LiveEventHandler starts and stops the event on every server.

return {
	Name = "liveevent",
	Description = "Start or stop the admin abuse live event on every server.",
	Group = "Admin",
	Args = {
		{
			Type = "string",
			Name = "action",
			Description = "start or stop.",
		},
		{
			Type = "string",
			Name = "script",
			Description = "Script id from Configs/AdminAbuse.Scripts; defaults to DefaultScript.",
			Optional = true,
		},
	},
}
