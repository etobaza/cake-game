--!strict
-- The HUD container: turns replicated player data into the strings and ratios the HUD shows, then
-- hands them to the hydrator.
--
-- This is the only layer that knows DataClient exists. The hydrator below it only knows which
-- element follows which value, and the layout itself stays in StarterGui.
--
-- DataClient arrives as a parameter rather than a require: Shared must never depend on Handlers, or
-- the server would pull client code in the moment it touched Shared.UI.

--[[ Services ]]--
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)
local Bus = require(_Shared.Bus)
local DayCycleConfig = require(_Configs.DayCycle)
local Format = require(_Shared.UI.Format)
local HydrateHud = require(_Shared.UI.HydrateHud)
local Motion = require(_Shared.UI.Motion)
local Pages = require(_Shared.UI.Stores.Pages)
local Progression = require(_Configs.Progression)
local UseClock = require(_Shared.UI.Hooks.UseClock)
local UseData = require(_Shared.UI.Hooks.UseData)

--[[ Constants ]]--
-- The shift countdown turns urgent this many seconds before the doors close.
local URGENT_SECONDS = 10

--[[ Types ]]--
export type Deps = {
	-- The DataHandlerClient handler.
	Data: any,
	-- Owned by whoever shows toasts.
	Status: any,
	StatusVisible: any,
	-- Owned by the tutorial.
	QuestText: any,
	QuestCount: any,
	QuestAlpha: any,
	HasQuest: any,
	-- Owned by whoever watches XP gains.
	XPText: any,
	XPVisible: any,
}

--[[ Handling ]]--
--- Binds `hud` (the HUD frame in the authored UI screen) to player data.
--- Call inside a Flux.scope.
return function(hud: Instance, deps: Deps): ()
	local data = deps.Data

	local cash = UseData.Path(data, { "Cash" }, "Cloud", 0)
	local level = UseData.Path(data, { "Level" }, "Cloud", 1)
	local xp = UseData.Path(data, { "XP" }, "Cloud", 0)
	local phase = UseData.Path(data, { "Day", "Phase" }, "Session", "Prep")
	local endsAt = UseData.Path(data, { "Day", "EndsAt" }, "Session", 0)
	local now = UseClock.Now()
	local clockMinutes = Flux(function(): number
		return DayCycleConfig.GetClockMinutes(phase(), endsAt(), now())
	end)

	-- Every client sees the atmosphere of their own bakery day. The HUD scope lives for the session;
	-- if it is ever remounted, put the place's authored time back before the new owner takes over.
	local authoredClockTime = Lighting.ClockTime
	Flux.cleanup(function()
		Lighting.ClockTime = authoredClockTime
	end)
	Flux(function()
		Lighting.ClockTime = if phase() == "Summary" or phase() == "Closing"
			then DayCycleConfig.EveningLightingHour
			else clockMinutes() / 60
	end, true)

	-- The level bar eases the way Animate.Fill used to.
	local levelAlpha = Motion.Spring(0, Motion.Presets.Gentle)

	-- Folded state of the quest panel; the arrow on the panel flips it.
	local questsCollapsed = Flux(false)

	-- The HUD leaves while any page is up: the page is the subject, the HUD is noise under it.
	local hudShown = Flux(function(): boolean
		return Pages.Current() == Pages.Names.None
	end)
	Flux(function()
		local toNext = Progression.GetXPToNext(level())
		levelAlpha(if toNext then math.clamp(xp() / toNext, 0, 1) else 1)
	end, true)

	HydrateHud(hud, {
		BalanceValue = cash,
		FormatBalance = function(value: number): string
			return `{Format.Number(value)}$`
		end,
		-- No friend-boost system yet; the authored line read +0%.
		FriendBoost = 'Friend Boost: <font color="#1EFF00">+0%</font>',

		-- The bakery clock is frozen at 08:00 during prep, advances to 16:00 during the shift,
		-- then stays at 16:00 while the evening menu is planned.
		Time = function(): string
			return Format.Clock(clockMinutes())
		end,
		Phase = phase,
		-- On while a running shift is nearly over; the clock plate knocks on every remaining second.
		TimeUrgent = function(): boolean
			local deadline = endsAt()
			return deadline > 0 and deadline - now() <= URGENT_SECONDS
		end,

		XPText = deps.XPText,
		XPVisible = deps.XPVisible,

		QuestText = deps.QuestText,
		QuestCount = deps.QuestCount,
		QuestAlpha = deps.QuestAlpha,
		HasQuest = deps.HasQuest,
		QuestsCollapsed = questsCollapsed,
		HudShown = hudShown,

		LevelText = function(): string
			local toNext = Progression.GetXPToNext(level())
			return if toNext then `Lvl {level()} - {xp()}/{toNext}` else `Lvl {level()} - max`
		end,
		LevelAlpha = levelAlpha,

		ShopLabel = "Shop",
		OnShop = function()
			Pages.Toggle(Pages.Names.Store)
		end,
		OnTime = function()
			if phase:peek() == "Prep" then
				Bus.Day.Open:Fire()
			end
		end,
		OnUpgrades = function()
			Pages.Toggle(Pages.Names.Upgrades)
		end,
		-- Playtime rewards live on the HUD Rewards button; daily rewards and codes stay on the topbar.
		OnRewards = function()
			Pages.Toggle(Pages.Names.Playtime)
		end,
		-- Daily rewards and codes are not on the HUD anymore: TopbarHandler puts them on the topbar.
		OnXPPlus = function()
			Pages.Toggle(Pages.Names.Store)
		end,
		-- The arrow folds the quest panel away instead of opening a page; playtime rewards live on
		-- the topbar now.
		OnQuestsToggle = function()
			questsCollapsed:set(not questsCollapsed:peek())
		end,
	})
end
