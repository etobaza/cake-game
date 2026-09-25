--!strict
-- Wires the UI up. It does not build any of it.
--
-- Every screen is authored in StarterGui and arrives in PlayerGui on its own, inside the folder the
-- UI package is mounted as; this module finds them under that root, binds the HUD to player data,
-- and makes each page's visibility follow Stores/Pages. That keeps the layout in the editor where
-- it can be drawn, and keeps the behaviour in code.
--
-- Returns the scope; destroy it to drop every binding and connection at once. The instances are not
-- ours and are left alone.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local BakeryMenu = require(_Shared.UI.BakeryMenu)
local Flux = require(_Packages.flux)
local HudComponent = require(_Shared.UI.Components.Hud)
local Pages = require(_Shared.UI.Stores.Pages)
local Responsive = require(_Shared.UI.Responsive)
local Scope = require(_Shared.UI.Scope)
local StatusLayout = require(_Shared.UI.StatusLayout)

--[[ Constants ]]--
local edit = Flux.edit
-- The authored HUD screen, and the frame inside it everything hangs off.
local HUD_SCREEN = "UI"
local HUD_ROOT = "HUD"
local FIND_TIMEOUT = 10
-- The panel inside a page: what actually springs in and out, since the ScreenGui itself has no size.
local PANEL_NAME = "MainFrame"
-- What a screen calls the button that closes it.
local CLOSE_NAMES = { "Exit", "CloseButton" }
-- The page whose close button is lent to pages drawn without one.
local CLOSE_DONOR = "Upgrades"
-- The status toast rides in its own screen above the pages (DisplayOrder 5 vs their 2), so a
-- message is never hidden behind an open page.
local STATUS_SCREEN = "Status"
local STATUS_FRAME = "StatusMessages"
local STATUS_LABEL = "Msg"
-- Focus feedback while a page is open: the backdrop screen (DisplayOrder 1, between the HUD and the
-- pages) dims the world, and the camera leans in a touch. Enough to feel, not enough to notice.
local BACKDROP_SCREEN = "Backdrop"
local BACKDROP_FRAME = "Dim"
local BACKDROP_ALPHA = 0.45
local FOCUS_FOV_DROP = 8

--[[ Types ]]--
export type Deps = HudComponent.Deps

export type Mounted = {
	Hud: ScreenGui,
	BakeryMenu: ScreenGui,
	HudRoot: Instance,
	Screens: { [string]: ScreenGui },
}

--[[ Private Functions ]]--
local function findClose(screen: Instance): GuiButton?
	for _, name in CLOSE_NAMES do
		local found = screen:FindFirstChild(name, true)
		if found and found:IsA("GuiButton") then
			return found
		end
	end

	return nil
end

-- A page that was drawn without a close button borrows one from a page that has it, so no screen is
-- a trap. This is authored art cloned whole -- only its parent changes -- not a button built here.
local function borrowClose(screen: ScreenGui, donor: GuiButton): GuiButton
	local main = screen:FindFirstChild("MainFrame")
	local host = (main and main:FindFirstChild("Header")) or main or screen
	local wrapper = donor.Parent
	if wrapper and wrapper:GetAttribute("CloseWrapper") then
		local clone = wrapper:Clone()
		clone.Parent = host
		return clone:FindFirstChild(donor.Name) :: GuiButton
	end
	local clone = donor:Clone()
	clone.Parent = host

	return clone
end

--[[ Handling ]]--
--- Binds every authored screen found directly under `root`. Returns the scope and what was found.
return function(deps: Deps, root: Instance): (Flux.Node<any>, Mounted)
	local hudScreen = root:WaitForChild(HUD_SCREEN, FIND_TIMEOUT) :: ScreenGui?
	if not hudScreen then
		error(`[UI.App] '{HUD_SCREEN}' is missing from {root:GetFullName()}`)
	end

	local hudRoot = hudScreen:WaitForChild(HUD_ROOT, FIND_TIMEOUT)
	if not hudRoot then
		error(`[UI.App] '{HUD_SCREEN}.{HUD_ROOT}' is missing`)
	end

	local statusScreen = root:WaitForChild(STATUS_SCREEN, FIND_TIMEOUT)
	local statusFrame = statusScreen and statusScreen:FindFirstChild(STATUS_FRAME)
	local backdropScreen = root:WaitForChild(BACKDROP_SCREEN, FIND_TIMEOUT)
	local dim = backdropScreen and backdropScreen:FindFirstChild(BACKDROP_FRAME)

	local screens: { [string]: ScreenGui } = {}
	-- Pages drawn without a close button, and the first button that can be lent to them.
	local needClose: { ScreenGui } = {}
	local donor: GuiButton? = nil

	--- Every authored screen, waited for rather than looked up: StarterGui is copied into PlayerGui
	--- one screen at a time, and on a slow boot the last of them is not there yet when this runs.
	--- Done before the scope, because a scope callback must not yield.
	local function collect(pageNames: { [string]: Pages.Page }): ()
		for _, pageName in pageNames do
			if pageName == Pages.Names.None then
				continue
			end

			local screen = root:WaitForChild(pageName, FIND_TIMEOUT)
			if screen and screen:IsA("ScreenGui") then
				screens[pageName] = screen
			else
				print(`[UI.App] '{pageName}' never arrived in {root:GetFullName()}`)
			end
		end
	end

	collect(Pages.Names)
	collect(Pages.Planned)
	local bakeryMenu = root:WaitForChild("BakeryMenu", FIND_TIMEOUT) :: ScreenGui
	assert(bakeryMenu and bakeryMenu:IsA("ScreenGui"), "[UI.App] StarterGui.BakeryMenu is missing")

	--- Visibility follows the store, and the screen's own close button clears it.
	---
	--- The ScreenGui is not bound straight to the store: it stays on while the panel springs away, or
	--- the page would vanish mid-animation. Opening pops the panel in, closing shrinks it and only
	--- then switches the screen off.
	local function bindPage(pageName: string): ()
		local screen = screens[pageName]
		if not screen then
			return
		end

		local panel = screen:FindFirstChild(PANEL_NAME)
		local isOpen = Pages.IsOpen(pageName)
		if BakeryMenu.Contains(pageName) then
			-- The shared header stays still; swapping tabs never leaves two panels in flight.
			edit(screen)({ Enabled = isOpen })
			return
		end

		if panel and panel:IsA("GuiObject") then
			Flux(function()
				if isOpen() then
					screen.Enabled = true
					Animate.Enter(panel)
				else
					Animate.ExitThen(panel, function()
						screen.Enabled = false
					end)
				end
			end, true)
		else
			edit(screen)({ Enabled = isOpen })
		end

		local close = findClose(screen)
		if not close then
			needClose[#needClose + 1] = screen
			return
		end

		donor = donor or close

		Animate.Press(close)
		edit(close)({
			Visible = function(): boolean
				return not Pages.Locked()
			end,
			Activated = function()
				Pages.Close()
			end,
		})
	end

	local scope = Scope.Run(function(): ()
		Flux.cleanup(Responsive.Bind(bakeryMenu))
		BakeryMenu.Bind(bakeryMenu, deps.Data)
		for _, screen in screens do
			Flux.cleanup(Responsive.Bind(screen))
		end
		-- The authored screen is left off in StarterGui so it does not cover the editor.
		edit(hudScreen)({ Enabled = true })
		HudComponent(hudRoot, deps)

		-- The status strip: text and visibility follow the toast nodes, and it rides in on each show.
		if statusScreen and statusScreen:IsA("ScreenGui") and statusFrame and statusFrame:IsA("GuiObject") then
			local statusLayout = StatusLayout.Bind(statusScreen, statusFrame)
			Flux.cleanup(function(): ()
				statusLayout:Destroy()
			end)
			edit(statusScreen)({ Enabled = true })
			edit(statusFrame)({ Visible = deps.StatusVisible })

			local message = statusFrame:FindFirstChild(STATUS_LABEL)
			if message and message:IsA("TextLabel") then
				edit(message)({ Text = deps.Status })
			end

			Flux(function()
				if Flux.read(deps.StatusVisible) then
					Animate.Enter(statusFrame)
				end
			end, true)
		else
			print(`[UI.App] '{STATUS_SCREEN}.{STATUS_FRAME}' is missing; toasts are disabled`)
		end

		-- Focus feedback: any open page dims the world and leans the camera in; closing undoes both.
		local nothingOpen = Flux(function(): boolean
			return Pages.Current() == Pages.Names.None
		end)

		if dim and dim:IsA("GuiObject") then
			local fade = Animate.Track(dim, "BackgroundTransparency", 1, function(value: number)
				dim.BackgroundTransparency = value
			end)

			Flux(function()
				fade:spring(if nothingOpen() then 1 else BACKDROP_ALPHA)
			end, true)
		else
			print(`[UI.App] '{BACKDROP_SCREEN}.{BACKDROP_FRAME}' is missing; pages will not dim the world`)
		end

		-- The spring writes through CurrentCamera on every step, so a camera swapped on respawn
		-- keeps answering; the base FOV is whatever the place was authored with.
		local camera = workspace.CurrentCamera
		local baseFov = if camera then camera.FieldOfView else 70
		local fov = Animate.Track(workspace, "FocusFov", baseFov, function(value: number)
			local current = workspace.CurrentCamera
			if current then
				current.FieldOfView = value
			end
		end)

		Flux(function()
			fov:spring(if nothingOpen() then baseFov else baseFov - FOCUS_FOV_DROP)
		end, true)

		-- Every authored screen is bound the same way, whether a system drives its contents yet or not.
		for pageName in screens do
			bindPage(pageName)
		end

		-- Pages are walked in table order, so the lender is named rather than "whichever came first":
		-- its button sits in a Header, which is where a borrowed one is parented.
		local preferred = screens[CLOSE_DONOR]
		donor = (preferred and findClose(preferred)) or donor

		for _, screen in needClose do
			if not donor then
				print(`[UI.App] '{screen.Name}' has no close button and there is none to lend it`)
				continue
			end

			local lent = borrowClose(screen, donor)

			Animate.Press(lent)
			edit(lent)({
				Visible = function(): boolean
					return not Pages.Locked()
				end,
				Activated = function()
					Pages.Close()
				end,
			})
		end
	end)

	return scope, {
		Hud = hudScreen,
		BakeryMenu = bakeryMenu,
		HudRoot = hudRoot,
		Screens = screens,
	}
end
