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
local HudReveal = require(_Shared.UI.Stores.HudReveal)
local InputCue = require(_Shared.UI.InputCue)
local InputCues = require(_Configs.InputCues)
local Motion = require(_Shared.UI.Motion)
local Pages = require(_Shared.UI.Stores.Pages)
local Progression = require(_Configs.Progression)
local Sunbeams = require(_Shared.Sunbeams)
local TutorialConfig = require(_Configs.Tutorial)
local UseClock = require(_Shared.UI.Hooks.UseClock)
local UseData = require(_Shared.UI.Hooks.UseData)
local Upgrades = require(_Configs.Registries.Upgrades)
local Wallet = require(_Shared.UI.Stores.Wallet)

--[[ Constants ]]--
-- The shift countdown turns urgent this many seconds before the doors close.
local URGENT_SECONDS = 10
local EARLY_OPEN = TutorialConfig.EarlyOpen
-- Side buttons with a controller shortcut: the authored button, its page and its key.
local SIDE_CUES: { { Button: string, Page: string, Key: Enum.KeyCode } } = {
	{ Button = "Upgrades", Page = Pages.Names.Upgrades, Key = InputCues.Keys.Upgrades },
	{ Button = "Shop", Page = Pages.Names.Store, Key = InputCues.Keys.Shop },
	{ Button = "Rewards", Page = Pages.Names.Playtime, Key = InputCues.Keys.Rewards },
}

--[[ Types ]]--
export type Deps = {
	-- The DataHandlerClient handler.
	Data: any,
	-- Owned by whoever shows toasts.
	Status: any,
	StatusVisible: any,
	-- Owned by HudHandler's next-upgrade goal.
	QuestText: any,
	QuestCount: any,
	QuestCost: any,
	QuestCostVisible: any,
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
	local friendPercent = UseData.Path(data, { "FriendBoost", "Percent" }, "Session", 0)
	-- Coins still flying into the plate are added as they land.
	local shownCash = Flux(function(): number
		local value = cash()
		return value - Wallet.Hold(value)
	end)
	local level = UseData.Path(data, { "Level" }, "Cloud", 1)
	local xp = UseData.Path(data, { "XP" }, "Cloud", 0)
	local upgradeCount = Flux(0)
	local function refreshUpgradeCount(): ()
		upgradeCount:set(Upgrades:ReadProgress(data).AffordableCount)
	end
	refreshUpgradeCount()
	Flux.cleanup(data:SubscribeToDataType("Cloud", refreshUpgradeCount))
	local phase = UseData.Path(data, { "Day", "Phase" }, "Session", "Prep")
	local day = UseData.Path(data, { "Day" }, "Cloud", 1)
	local endsAt = UseData.Path(data, { "Day", "EndsAt" }, "Session", 0)
	local shiftSeconds = UseData.Path(data, { "Day", "ShiftSeconds" }, "Session", 0)
	local now = UseClock.Now()
	local clockMinutes = Flux(function(): number
		return DayCycleConfig.GetClockMinutes(phase(), endsAt(), shiftSeconds(), now())
	end)

	-- Every client sees the atmosphere of their own bakery day. The HUD scope lives for the session;
	-- if it is ever remounted, put the place's authored time back before the new owner takes over.
	local authoredClockTime = Lighting.ClockTime
	local sunbeams = Sunbeams.new()
	Flux.cleanup(function()
		Lighting.ClockTime = authoredClockTime
		sunbeams:Destroy()
	end)
	Flux(function()
		local evening = phase() == "Summary" or phase() == "Closing"
		Lighting.ClockTime = if evening then DayCycleConfig.EveningLightingHour else clockMinutes() / 60
		sunbeams:SetEvening(evening)
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

	-- The clock plate's sign opens the bakery while it still reads Closed.
	local function openBakery(): ()
		if phase:peek() == "Prep" then
			Bus.Day.Open:Fire()
		end
	end

	HydrateHud(hud, {
		BalanceValue = shownCash,
		FormatBalance = function(value: number): string
			return `{Format.Number(value)}$`
		end,
		FriendBoost = function(): string
			return `Friend Boost: <font color="#1EFF00">+{friendPercent()}%</font>`
		end,

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
		-- A new baker's closed sign knocks every few seconds of the morning until the bakery opens.
		OpenBeat = function(): number?
			local calling = phase() == "Prep"
				and day() <= EARLY_OPEN.MaxDay
				and HudReveal.Shown("Time")
				and Pages.Current() == Pages.Names.None
			return if calling then math.floor(now() / EARLY_OPEN.KnockSeconds) else nil
		end,

		XPText = deps.XPText,
		XPVisible = deps.XPVisible,

		QuestText = deps.QuestText,
		QuestCount = deps.QuestCount,
		QuestCost = deps.QuestCost,
		QuestCostVisible = deps.QuestCostVisible,
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
		UpgradesAvailable = upgradeCount,
		OnShop = function()
			Pages.Toggle(Pages.Names.Store)
		end,
		OnTime = openBakery,
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

	-- Controller badges on the side buttons. An open page owns the D-pad for its selection, and B closes it.
	local sideButtons = hud:FindFirstChild("SideBtns")
	for _, cue in SIDE_CUES do
		local target = sideButtons and sideButtons:FindFirstChild(cue.Button)
		if not target or not target:IsA("GuiObject") then
			print(`[Hud] no side button '{cue.Button}' for its input cue`)
			continue
		end
		local binding = InputCue.Bind({
			Name = cue.Button,
			Target = target,
			Key = cue.Key,
			Placement = "Edge",
			Action = function(): ()
				Pages.Open(cue.Page)
			end,
			Available = function(): boolean
				return Pages.Current:peek() == Pages.Names.None and InputCue.OnScreen(target)
			end,
		})
		Flux.cleanup(function(): ()
			binding:Destroy()
		end)
	end

	-- The clock sits far from the side buttons, so a controller opens the bakery with its own key
	-- instead of walking the selection up to it. The badge shows only while the sign reads Closed and
	-- the introduction has revealed the clock (a hidden group is slid off screen, still Visible).
	local clock = hud:FindFirstChild("Time")
	if clock and clock:IsA("GuiObject") then
		local function closed(): boolean
			return phase:peek() == "Prep" and HudReveal.Shown("Time")
		end
		local clockCue = InputCue.Bind({
			Name = "OpenBakery",
			Target = clock,
			Key = InputCues.Keys.OpenBakery,
			Action = openBakery,
			Available = function(): boolean
				return closed() and Pages.Current:peek() == Pages.Names.None and InputCue.OnScreen(clock)
			end,
			Shown = closed,
		})
		Flux(function()
			local _phase = phase()
			local _revealed = HudReveal.Shown("Time")
			clockCue:Refresh()
		end, true)
		Flux.cleanup(function(): ()
			clockCue:Destroy()
		end)
	else
		print("[Hud] no clock plate 'Time' for its input cue")
	end
end
