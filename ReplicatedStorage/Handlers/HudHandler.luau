--!strict
-- Feeds the HUD its earned-XP notification; ReportHandler owns shift results.
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
	-- The introduction owns StarterGui.Tutorial; the retired HUD quest slot stays hidden.
	UIHandler.HasQuest:set(false)
	self:Refresh()

	DataClient:SubscribeToDataType("Cloud", function()
		self:Refresh()
	end)
end

function HudHandler.Refresh(self: HudHandler): ()
	local level = DataClient:GetData({ "Level" }) or 1
	local xp = DataClient:GetData({ "XP" }) or 0

	self:RefreshXP(level, xp)
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
