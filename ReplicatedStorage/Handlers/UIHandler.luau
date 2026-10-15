--!strict
-- Wires the UI up and owns the pieces every screen shares: the status strip, the quest line, the XP
-- notification and the page routing.
--
-- The layout stays authored in StarterGui. Shared/UI/App finds those screens and binds them with
-- Flux, so a redesign in the editor needs no code change as long as the names hold.
--
-- Screens that want a value on screen write to a node here; nothing pokes a label directly.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local FoodPreview = require(_Shared.UI.FoodPreview)
local App = require(_Shared.UI.App)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local Flux = require(_Packages.flux)
local Format = require(_Shared.UI.Format)
local UIText = require(_Configs.UIText)

--[[ Constants ]]--
-- The screens ship as one Roblox package, so StarterGui copies them into PlayerGui inside this folder.
local SCREENS_FOLDER = "MainGui"
local SCREENS_TIMEOUT = 10
local TOAST_SECONDS = 2.5
-- The XP plate is a notification: it slides in with what was just earned and leaves.
local XP_SECONDS = 2.5

--[[ Tables ]]--
local UIHandler = {
	-- The HUD binds player data the moment it binds, so the cache has to exist first.
	dependencies = { "DataClient" },
	-- It owns the screens, so it starts before anything that wants to drive one.
	priority = 90,
}

--[[ Handling ]]--
--- Only the nodes are made here. Binding waits for OnStart: the HUD subscribes to DataClient the
--- moment it binds, and DataClient creates its signals in its own OnStart, which has not run yet.
function UIHandler.OnInit(self: UIHandler): ()
	-- Everything the screens display that is not read straight from player data.
	self.Status = Flux("")
	self.StatusVisible = Flux(false)
	self.QuestText = Flux("")
	self.QuestCount = Flux("")
	self.QuestCost = Flux("")
	self.QuestCostVisible = Flux(false)
	self.QuestAlpha = Flux(0)
	self.HasQuest = Flux(false)
	self.XPText = Flux("")
	self.XPVisible = Flux(false)
	self.ToastToken = 0
	self.XPToken = 0
end

function UIHandler.OnStart(self: UIHandler): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- StarterGui is copied in with the first character, which the server spawns only once the
	-- profile has loaded; like the data wait below, this has no deadline.
	local screensRoot = playerGui:WaitForChild(SCREENS_FOLDER)

	-- The first snapshot arrives as one push and does not ring the per-path signals, so a node bound
	-- before it lands keeps its placeholder until something happens to change that field. Waiting
	-- here means every HUD node reads a real value the moment it is created.
	DataClient:WaitForData()

	local scope, mounted = App({
		Data = DataClient,
		Status = self.Status,
		StatusVisible = self.StatusVisible,
		QuestText = self.QuestText,
		QuestCount = self.QuestCount,
		QuestCost = self.QuestCost,
		QuestCostVisible = self.QuestCostVisible,
		QuestAlpha = self.QuestAlpha,
		HasQuest = self.HasQuest,
		XPText = self.XPText,
		XPVisible = self.XPVisible,
	}, screensRoot)

	self.Scope = scope
	self.Hud = mounted.Hud
	self.BakeryMenu = mounted.BakeryMenu
	FoodPreview.SetTemplate(mounted.Hud:FindFirstChild("FoodPreviewTemplate"))
	-- Overlay surface for screens that build their own instances (guide markers, spotlight).
	-- It used to be the MainUI ScreenGui; the HUD screen serves the same purpose.
	self.Gui = mounted.Hud
	self.Screens = mounted.Screens
	-- Tutorial is an overlay, outside the mutually exclusive modal page router.
	local tutorial = screensRoot:WaitForChild("Tutorial", SCREENS_TIMEOUT)
	if tutorial and tutorial:IsA("ScreenGui") then
		self.Screens.Tutorial = tutorial
	end
	self.HudRoot = mounted.HudRoot :: Frame

	Bus.Progress.ActionFailed.OnClientEvent:Connect(function(reason: string)
		self:Toast(UIText.GetFailure(reason))
	end)

	-- Level ups get FeedbackHandler's full-screen banner instead of a toast.
	Bus.Day.StoryUnlocked.OnClientEvent:Connect(function(stage: number)
		self:Toast(`Story chapter {stage} unlocked`)
	end)
end

--- HUD element by its path under the HUD frame: "Currency.Main.CoinBalance".
function UIHandler.GetHud(self: UIHandler, path: string): Instance
	local current: Instance = self.HudRoot

	for _, name in string.split(path, ".") do
		local child = current:FindFirstChild(name)
		if not child then
			error(`[UIHandler] HUD element not found: {path}`)
		end

		current = child
	end

	return current
end

--- A full-screen page by name, or nil if there is no such screen.
--- Returns nil rather than erroring: MainUI was lost with its panels, and a caller that wants one of
--- those should degrade instead of taking the whole client down with it.
function UIHandler.GetPanel(self: UIHandler, panelName: string): ScreenGui?
	local screen = self.Screens[panelName]
	if not screen then
		print(`[UIHandler] no screen named '{panelName}'`)
	end

	return screen
end

--- Short message in the HUD status strip. Returns a token for `ClearToast`.
function UIHandler.Toast(self: UIHandler, text: string): number
	self.ToastToken += 1
	local token = self.ToastToken

	self.Status:set(text)
	self.StatusVisible:set(true)

	task.delay(TOAST_SECONDS, function()
		-- A newer toast replaced this one: hiding it is not our job anymore.
		if self.ToastToken ~= token then
			return
		end

		self.StatusVisible:set(false)
	end)

	return token
end

--- Hides the toast early, but only while it is still the one identified by `token`.
function UIHandler.ClearToast(self: UIHandler, token: number): ()
	if self.ToastToken == token then
		self.StatusVisible:set(false)
	end
end

--- XP notification: slides the XP plate in from the right with `text`, and back out after
--- `seconds` (default XP_SECONDS). Callers pass what was just earned, not a running total.
function UIHandler.NotifyXP(self: UIHandler, text: string, seconds: number?): ()
	self.XPToken += 1
	local token = self.XPToken

	self.XPText:set(text)
	self.XPVisible:set(true)

	task.delay(seconds or XP_SECONDS, function()
		-- A newer notification replaced this one: hiding it is not our job anymore.
		if self.XPToken ~= token then
			return
		end

		self.XPVisible:set(false)
	end)
end

--- 1234 -> "1 234": long amounts are unreadable otherwise.
function UIHandler.FormatNumber(_self: UIHandler, value: number): string
	return Format.Number(value)
end

export type UIHandler = typeof(UIHandler) & {
	Scope: any,
	Hud: ScreenGui,
	BakeryMenu: ScreenGui,
	Gui: ScreenGui,
	HudRoot: Frame,
	Screens: { [string]: ScreenGui },
	Status: Flux.Node<string>,
	StatusVisible: Flux.Node<boolean>,
	QuestText: Flux.Node<string>,
	QuestCount: Flux.Node<string>,
	QuestCost: Flux.Node<string>,
	QuestCostVisible: Flux.Node<boolean>,
	QuestAlpha: Flux.Node<number>,
	HasQuest: Flux.Node<boolean>,
	XPText: Flux.Node<string>,
	XPVisible: Flux.Node<boolean>,
	ToastToken: number,
	XPToken: number,
}

return UIHandler :: UIHandler
