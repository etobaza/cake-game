--!strict
-- Presentation and bounds only. Authorization lives in ServerScriptService.Cmdr.Admin.

export type Action = {
	id: string,
	label: string,
	section: string,
	max: number?,
	allowZero: boolean?,
	warning: string?,
}

local actions: { Action } = {
	{ id = "addCash", label = "Add coins", section = "Resources", max = 1000000 },
	{
		id = "setCash",
		label = "Set balance",
		section = "Resources",
		max = 100000000,
		allowZero = true,
		warning = "This replaces the current balance.",
	},
	{ id = "addXP", label = "Add XP", section = "Resources", max = 100000 },
	{
		id = "stockPantry",
		label = "Add all ingredients",
		section = "Resources",
		max = 1000,
	},
	{ id = "upgradeMoney", label = "Fund remaining upgrades", section = "Progress" },
	{ id = "unlockUpgrades", label = "Unlock all upgrades", section = "Progress" },
	{ id = "skipTutorial", label = "Skip tutorial", section = "Tutorial" },
	{
		id = "resetTutorial",
		label = "Restart tutorial",
		section = "Tutorial",
		warning = "The kitchen will be preserved; the tutorial will restart.",
	},
	{ id = "openBakery", label = "Open bakery", section = "Shift" },
	{ id = "endShift", label = "End shift", section = "Shift" },
	{ id = "nextDay", label = "Next day", section = "Shift" },
	{
		id = "clearHands",
		label = "Clear hands",
		section = "Recovery",
		warning = "The held item will be removed; a held tool will return to its stand.",
	},
	{ id = "respawn", label = "Respawn character", section = "Recovery" },
	{ id = "resync", label = "Resync client data", section = "Recovery" },
	{
		id = "resetProgress",
		label = "RESET PROGRESS",
		section = "Danger zone",
		warning = "This deletes gameplay progress and disconnects the player. They must rejoin. Purchases, skins, and receipt history are preserved. This cannot be undone.",
	},
}

local byId: { [string]: Action } = {}
for _, action in actions do
	byId[action.id] = action
end

return {
	Actions = actions,
	ById = byId,
	MaxCash = 100000000,
	MaxPantry = 100000,
	RequestCooldown = 0.4,
	ConfirmationSeconds = 30,
	AccessAttribute = "AdminPanelAccess",
	DisplayOrder = 100,
}
