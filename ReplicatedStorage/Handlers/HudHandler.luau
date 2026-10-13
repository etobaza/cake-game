--!strict
-- Feeds the HUD its earned-XP notification and next-upgrade goal; ReportHandler owns shift results.
--
-- Everything else the old HudHandler drove -- coins, the level bar, the clock, the phase icon, the
-- buttons -- is bound straight from DataClient inside Shared/UI/Components/Hud now. This handler
-- writes to nodes and never touches an instance.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local DataClient = require(_Handlers.DataHandlerClient)
local Format = require(_Shared.UI.Format)
local Progression = require(_Configs.Progression)
local UIHandler = require(_Handlers.UIHandler)
local Upgrades = require(_Configs.Registries.Upgrades)

--[[ Tables ]]--
local HudHandler = {
	-- UIHandler creates the notification nodes before this handler writes to them.
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Handling ]]--
function HudHandler.OnInit(self: HudHandler): ()
	-- -1 marks "no snapshot yet": the first data arrival is not a gain and must not pop.
	self.XPLevel = -1
	self.XPValue = 0
end

function HudHandler.OnStart(self: HudHandler): ()
	DataClient:WaitForData()
	self:Refresh()

	DataClient:SubscribeToDataType("Cloud", function()
		self:Refresh()
	end)
end

function HudHandler.Refresh(self: HudHandler): ()
	local level = DataClient:GetData({ "Level" }) or 1
	local xp = DataClient:GetData({ "XP" }) or 0

	self:RefreshXP(level, xp)
	self:RefreshGoal(level)
end

function HudHandler.RefreshGoal(_self: HudHandler, playerLevel: number): ()
	local levels = DataClient:GetData({ "Base", "Upgrades" }) or {}
	local cash = DataClient:GetData({ "Cash" }) or 0
	local progress = Upgrades:GetProgress(levels, playerLevel, cash)
	local goal = progress.Goal
	UIHandler.HasQuest:set(true)
	UIHandler.QuestCost:set("")
	UIHandler.QuestCostVisible:set(false)
	if progress.Complete then
		UIHandler.QuestText:set("All upgrades purchased!")
		UIHandler.QuestCount:set("Complete")
		UIHandler.QuestAlpha:set(1)
		return
	end
	if not goal then
		return
	end
	local name = Upgrades:GetDisplayName(goal.Id, goal.Level - 1)
	if progress.Recommended then
		local costText = Format.Money(goal.Cost)
		UIHandler.QuestCost:set(`{costText}$`)
		UIHandler.QuestCostVisible:set(true)
		UIHandler.QuestText:set(if cash >= goal.Cost then `Buy {name}` else `Save for {name}`)
		UIHandler.QuestCount:set(`{Format.Money(cash)}$/{costText}$`)
		UIHandler.QuestAlpha:set(math.clamp(cash / goal.Cost, 0, 1))
		return
	end
	-- Future level-gated registries still expose a goal without calling it purchasable.
	local entry = Upgrades:Get(goal.Id)
	local missing = entry and Upgrades:GetMissingRequirement(entry, levels)
	local requirement = if missing then Upgrades:GetDisplayName(missing, levels[missing] or 0)
		else `level {if entry then entry.unlockLevel else playerLevel + 1}`
	UIHandler.QuestText:set(`Unlock {name}`)
	UIHandler.QuestCount:set(`Requires {requirement}`)
	UIHandler.QuestAlpha:set(0)
end

--- XP arrives as a notification: the plate slides in with what was just earned and leaves. The
--- running total lives on the level line, so nothing here shows it.
---
--- A level up resets the counter, so the part spent on reaching the new level is added back instead
--- of reading as a loss.
function HudHandler.RefreshXP(self: HudHandler, level: number, xp: number): ()
	local previousLevel = self.XPLevel
	local previous = self.XPValue

	self.XPLevel = level
	self.XPValue = xp

	if previousLevel < 0 then
		return
	end

	local gained = xp - previous
	if level > previousLevel then
		gained = (Progression.GetXPToNext(previousLevel) or previous) - previous + xp
	end

	if gained <= 0 then
		return
	end

	UIHandler:NotifyXP(`+{Format.Number(gained)}XP`)
end

export type HudHandler = typeof(HudHandler) & {
	XPLevel: number,
	XPValue: number,
}

return HudHandler :: HudHandler
