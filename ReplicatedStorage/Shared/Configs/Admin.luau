--!strict
-- Presentation and bounds only. Authorization lives in ServerScriptService.Cmdr.Admin.

local AdminAbuse = require(script.Parent.AdminAbuse)

-- Live event actions are this prefix plus a script id from Configs/AdminAbuse.
local LIVE_EVENT_PREFIX = "liveEvent:"

export type Action = {
	id: string,
	label: string,
	section: string,
	max: number?,
	allowZero: boolean?,
	warning: string?,
	-- Accept button text on the confirmation step; the panel defaults to "CONFIRM".
	confirmLabel: string?,
	-- Acts on every server instead of the selected player; no profile is needed.
	global: boolean?,
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
		confirmLabel = "RESET PROGRESS",
		warning = "This deletes gameplay progress and disconnects the player. They must rejoin. Purchases, skins, and receipt history are preserved. This cannot be undone.",
	},
}

-- One start button per live event script, then a stop button.
local scriptIds: { string } = {}
for scriptId in AdminAbuse.Scripts do
	scriptIds[#scriptIds + 1] = scriptId
end
table.sort(scriptIds)
for _, scriptId in scriptIds do
	actions[#actions + 1] = {
		id = `{LIVE_EVENT_PREFIX}{scriptId}`,
		label = `Start: {AdminAbuse.Scripts[scriptId].Name}`,
		section = "Live event",
		global = true,
		warning = "Starts the admin abuse event on every server.",
	}
end
actions[#actions + 1] = {
	id = "liveEventStop",
	label = "Stop live event",
	section = "Live event",
	global = true,
	warning = "Stops the admin abuse event on every server.",
}

local byId: { [string]: Action } = {}
for _, action in actions do
	byId[action.id] = action
end

return {
	Actions = actions,
	ById = byId,
	LiveEventPrefix = LIVE_EVENT_PREFIX,
	MaxCash = 100000000,
	MaxPantry = 100000,
	RequestCooldown = 0.4,
	ConfirmationSeconds = 30,
	AccessAttribute = "AdminPanelAccess",
	DisplayOrder = 100,
	-- The panel toggle sits at the right end of Roblox's topbar row, clear of every HUD group. Touch
	-- has no F4 key, so it drops the hint there and keeps a touch-sized height.
	Toggle = {
		Text = "ADMIN • F4",
		TouchText = "ADMIN",
		Size = Vector2.new(124, 36),
		TouchSize = Vector2.new(84, 44),
		-- Pixels left free at the row's right end for the tutorial's help button.
		RightClearance = 60,
	},
}
