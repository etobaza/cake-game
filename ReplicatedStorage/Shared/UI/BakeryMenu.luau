--!strict
-- One authored header stays in place while the bakery's report, menu and upgrades switch.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--[[ Modules ]]--
local Animate = require(script.Parent.Animate)
local ButtonRow = require(script.Parent.ButtonRow)
local Flux = require(ReplicatedStorage.Packages.flux)
local InputCue = require(script.Parent.InputCue)
local InputCues = require(ReplicatedStorage.Shared.Configs.InputCues)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local MenuPlan = require(ReplicatedStorage.Shared.Tutorial.MenuPlan)
local Pages = require(script.Parent.Stores.Pages)
local Press = require(script.Parent.Press)
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)
local UseData = require(script.Parent.Hooks.UseData)

--[[ Constants ]]--
local TABS: { [string]: Pages.Page } = {
	Report = Pages.Names.Report,
	Upgrades = Pages.Names.Upgrades,
	Menu = Pages.Names.Inventory,
}
local TAB_BUTTONS = { "Report", "Upgrades", "Menu" }
local HEADER_LEFT_INSET = 6
local HEADER_RIGHT_INSET = 6
local HEADER_GAP = 8
local HEADER_Y = -22
local RIBBON_OVERHANG = 64
local SELECTED = Color3.fromRGB(247, 233, 205)
local IDLE = Color3.fromRGB(205, 191, 161)
local DISABLED = Color3.fromRGB(150, 143, 127)
-- Next Day is the evening's one forward action: wider than a tab (in tab widths) and set further apart
-- from them. Its authored art (the tabs' stitched plate in green, sunrise, arrows) lives in the place.
local NEXT_DAY_SHARE = 1.15
local NEXT_DAY_GAP = 24
-- Kept from the ribbon's end so the hovered button still shows a red rim there.
local NEXT_DAY_INSET = 16
-- A light band sweeps across the face between pauses, and the sunrise bobs.
local NEXT_DAY_SHINE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.4)
local NEXT_DAY_SHINE_FROM = Vector2.new(-1, 0)
local NEXT_DAY_SHINE_TO = Vector2.new(1, 0)
local NEXT_DAY_BOB = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local NEXT_DAY_BOB_RISE = 2
-- The HUD's alert badge, from the mounted UI root, sized by the tab's height at its top-right corner.
local ALERT_SOURCE = { "UI", "HUD", "SideBtns", "Rewards", "Mark" }
local ALERT_SIZE = UDim2.fromScale(0.55, 0.5)
local ALERT_POSITION = UDim2.fromScale(0.97, 0.1)

--[[ Tables ]]--
local BakeryMenu = {}

--[[ Handling ]]--
function BakeryMenu.Contains(page: string): boolean
	return page == Pages.Names.Report or page == Pages.Names.Inventory or page == Pages.Names.Upgrades
end

-- Called inside App's Flux scope. MenuHandler owns the Next Day action and its validation.
function BakeryMenu.Bind(screen: ScreenGui, data: any): ()
	local panel = screen:FindFirstChild("MainFrame") :: Frame
	local header = panel:FindFirstChild("Header") :: Frame
	local buttons = header:FindFirstChild("Buttons") :: Frame
	-- The page background starts at y = 42. Keep the 56px ribbon eight pixels above it.
	local headerPosition = UDim2.fromOffset(0, HEADER_Y)
	header.Position = headerPosition
	header:SetAttribute("WidePosition", headerPosition)
	header:SetAttribute("CompactPosition", headerPosition)
	local background = header:FindFirstChild("Bg") :: ImageLabel
	-- Extend the existing tail outside the page without shifting the tab row.
	background.AnchorPoint = Vector2.new(1, 0.5)
	background.Position = UDim2.fromScale(1, 0.5)
	background.Size = UDim2.new(1, RIBBON_OVERHANG, 1, 0)
	local phase = UseData.Path(data, { "Day", "Phase" }, "Session", "Prep")
	local isSummary = Flux(function(): boolean
		return phase() == "Summary"
	end)
	-- Before opening, once the introduction is over, today's menu can still change (MenuHandler.CanEdit),
	-- so the Upgrades and Menu tabs show without the report and Next Day.
	local tutorialStatus = UseData.Path(data, { "Tutorial", "Status" }, "Cloud", "")
	local menuToday = Flux(function(): boolean
		return phase() == "Prep" and not TutorialPolicy.IsActive({ Tutorial = { Status = tutorialStatus() } })
	end)
	local showTabs = Flux(function(): boolean
		return isSummary() or menuToday()
	end)
	local function tabAvailable(page: Pages.Page): boolean
		return (isSummary() or (menuToday() and page ~= Pages.Names.Report)) and Pages.CanOpen(page)
	end
	local janitor = Janitor.new()
	Flux.cleanup(function(): ()
		janitor:Destroy()
	end)
	janitor:LinkToInstance(screen)
	local function bindPress(button: GuiButton): ()
		local reset = Animate.Press(button, nil, janitor)
		-- Closing can hide the screen without MouseLeave; each visibility cycle starts at rest.
		janitor:Add(screen:GetPropertyChangedSignal("Enabled"):Connect(reset), "Disconnect")
		janitor:Add(button:GetPropertyChangedSignal("Visible"):Connect(reset), "Disconnect")
		janitor:Add(button:GetPropertyChangedSignal("Interactable"):Connect(reset), "Disconnect")
	end
	Flux.edit(screen)({
		Enabled = function(): boolean
			return BakeryMenu.Contains(Pages.Current()) and not Pages.Presenting()
		end,
	})
	-- Standalone pages use the full-size authored ribbon title, not a small tab caption.
	local title = header:FindFirstChild("Title") :: Frame
	Flux.edit(title)({
		Visible = function(): boolean
			return not showTabs()
		end,
	})
	for _, label in title:GetChildren() do
		if not label:IsA("TextLabel") then
			continue
		end
		Flux.edit(label)({
			Text = function(): string
				local page = Pages.Current()
				return if page == Pages.Names.Inventory then "Menu" else page
			end,
		})
	end
	-- Align the outer tab edges with the page background's six-pixel side insets.
	local rowPosition = UDim2.new(1, -HEADER_RIGHT_INSET + HEADER_GAP / 2, 0.5, 0)
	local rowSize = UDim2.new(1, -HEADER_LEFT_INSET - HEADER_RIGHT_INSET + HEADER_GAP, 0, 44)
	buttons.AnchorPoint = Vector2.new(1, 0.5)
	buttons:SetAttribute("WidePosition", rowPosition)
	buttons:SetAttribute("CompactPosition", rowPosition)
	buttons:SetAttribute("WideSize", rowSize)
	buttons:SetAttribute("CompactSize", rowSize)
	Flux.edit(buttons)({
		Visible = showTabs,
		Position = rowPosition,
		Size = rowSize,
	})
	-- The page panels are authored as selection groups that stop the D-pad at every edge. This header
	-- is a separate screen, so in the evening their top edge lets the D-pad up onto the tabs and Next Day.
	for _, page in TABS do
		local pageScreen = screen.Parent and screen.Parent:FindFirstChild(page)
		local pagePanel = pageScreen and pageScreen:FindFirstChild("MainFrame")
		if not pagePanel or not pagePanel:IsA("GuiObject") then
			continue
		end
		local authoredUp = pagePanel.SelectionBehaviorUp
		Flux.edit(pagePanel)({
			SelectionBehaviorUp = function(): Enum.SelectionBehavior
				return if showTabs() then Enum.SelectionBehavior.Escape else authoredUp
			end,
		})
	end
	local rowButtons: { GuiObject } = {}
	local tabShare = 1 / (#TAB_BUTTONS + NEXT_DAY_SHARE)
	for index, name in TAB_BUTTONS do
		local button = buttons:FindFirstChild(name) :: TextButton
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale((index - 0.5) * tabShare, 0.5)
		button.Size = UDim2.new(tabShare, -HEADER_GAP, 1, 0)
		local lines = button:FindFirstChild("Lines") :: ImageLabel
		lines.AnchorPoint = Vector2.new(0.5, 0.5)
		lines.Position = UDim2.fromScale(0.5, 0.5)
		table.insert(rowButtons, button)
	end
	-- Next Day fills the rest of the row, stopping NEXT_DAY_INSET short of the ribbon's end.
	local nextDay = buttons:FindFirstChild("NextDay") :: TextButton
	local nextDayShift = NEXT_DAY_INSET - HEADER_RIGHT_INSET
	nextDay.AnchorPoint = Vector2.new(1, 0.5)
	nextDay.Position = UDim2.new(1, -HEADER_GAP / 2 - nextDayShift, 0.5, 0)
	nextDay.Size = UDim2.new(1 - #TAB_BUTTONS * tabShare, -NEXT_DAY_GAP - nextDayShift, 1, 0)
	table.insert(rowButtons, nextDay)
	janitor:Add(ButtonRow.Bind(buttons, rowButtons), "Destroy")
	BakeryMenu.BindMenuAlert(screen, buttons:FindFirstChild("Menu") :: GuiObject, data)
	-- The shoulder buttons walk the evening tabs, skipping any the lock refuses.
	local function step(direction: number): ()
		local index = 1
		for position, name in TAB_BUTTONS do
			if TABS[name] == Pages.Current:peek() then
				index = position
			end
		end
		for offset = 1, #TAB_BUTTONS - 1 do
			local page = TABS[TAB_BUTTONS[(index - 1 + direction * offset) % #TAB_BUTTONS + 1]]
			if tabAvailable(page) then
				Pages.Open(page)
				return
			end
		end
	end
	-- The upgrade tree uses the same shoulder buttons for its categories, so it keeps them.
	local function shoulders(): boolean
		return Pages.Current:peek() ~= Pages.Names.Upgrades
	end
	local previousTab = buttons:FindFirstChild(TAB_BUTTONS[1]) :: GuiObject
	local nextTab = buttons:FindFirstChild(TAB_BUTTONS[#TAB_BUTTONS]) :: GuiObject
	local tabCues = {
		InputCue.Bind({
			Name = "EveningPreviousTab",
			Target = previousTab,
			Key = InputCues.Keys.PreviousTab,
			-- On the tabs' outer edges: the row leaves no room beside them, Next Day sits close by.
			Placement = "LeftEdge",
			Action = function(): ()
				step(-1)
			end,
			Available = function(): boolean
				return shoulders() and InputCue.OnScreen(previousTab)
			end,
			Shown = shoulders,
		}),
		InputCue.Bind({
			Name = "EveningNextTab",
			Target = nextTab,
			Key = InputCues.Keys.NextTab,
			Placement = "Edge",
			Action = function(): ()
				step(1)
			end,
			Available = function(): boolean
				return shoulders() and InputCue.OnScreen(nextTab)
			end,
			Shown = shoulders,
		}),
	}
	for _, cue in tabCues do
		janitor:Add(cue, "Destroy")
	end
	Flux(function(): ()
		Pages.Current()
		for _, cue in tabCues do
			cue:Refresh()
		end
	end, true)
	for name, page in TABS do
		local button = buttons:FindFirstChild(name) :: TextButton
		local available = Flux(function(): boolean
			return tabAvailable(page)
		end)
		Flux.edit(button)({
			Interactable = available,
			Selectable = available,
			Activated = function(): ()
				if available:peek() then
					Pages.Open(page)
				end
			end,
		})
		Flux.edit(button:FindFirstChild("Bg", true) :: Frame)({
			BackgroundColor3 = function(): Color3
				return if not available() then DISABLED else if Pages.Current() == page then SELECTED else IDLE
			end,
		})
	end
	Flux.edit(nextDay)({
		Visible = isSummary,
	})
	BakeryMenu.AnimateNextDay(nextDay, isSummary, janitor)
	local close = header:FindFirstChild("Exit", true) :: GuiButton
	-- B presses it, so gamepad focus stays on the page's content.
	close.Selectable = false
	bindPress(close)
	janitor:Add(InputCue.Bind({ Target = close, Key = InputCues.Keys.Close }), "Destroy")
	Flux.edit(close)({
		Visible = function(): boolean
			return not Pages.Locked()
		end,
		Activated = function(): ()
			Pages.Close()
		end,
	})
	-- The cross is under 20 pixels on a phone, so a touch pad around it takes pointer presses.
	local pad = Press.TouchPad(close)
	pad.Selectable = false
	local resetPad = Animate.Press(pad, close, janitor)
	janitor:Add(screen:GetPropertyChangedSignal("Enabled"):Connect(resetPad), "Disconnect")
	janitor:Add(Press.BindTap(pad, function(): ()
		Pages.Close()
	end), "Destroy")
end

-- The HUD's alert mark on the Menu tab while an unlocked dish the player can make is left off
-- tomorrow's menu and there is room for it. Menu editing stays an evening task.
function BakeryMenu.BindMenuAlert(screen: ScreenGui, tab: GuiObject, data: any): ()
	local source: Instance? = screen.Parent
	for _, name in ALERT_SOURCE do
		source = source and source:FindFirstChild(name)
	end
	if not source or not source:IsA("GuiObject") then
		print("[BakeryMenu] no HUD alert artwork for the Menu tab")
		return
	end
	-- StarterGui is place-only, so the authored reward alert is lent; the scope owns this copy.
	local mark = source:Clone()
	mark.Active = false
	mark.Selectable = false
	mark.Interactable = false
	mark.SizeConstraint = Enum.SizeConstraint.RelativeYY
	mark.Size = ALERT_SIZE
	mark.Position = ALERT_POSITION
	mark.Parent = tab
	Flux.cleanup(mark)
	local missing = Flux(false)
	local function refresh(): ()
		local cloud = data:GetData({}, "Cloud")
		local session = data:GetData({}, "Session")
		missing:set(
			cloud ~= nil
				and session ~= nil
				and session.Day.Phase == "Summary"
				and MenuPlan.Missing(cloud, session) ~= nil
		)
	end
	refresh()
	Flux.cleanup(data:SubscribeToDataType("Cloud", refresh))
	Flux.cleanup(data:SubscribeToDataType("Session", refresh))
	Flux.edit(mark)({ Visible = missing })
end

-- Runs only while the button shows; hiding it returns the shine and the sunrise to rest.
function BakeryMenu.AnimateNextDay(button: GuiButton, shown: () -> boolean, janitor: any): ()
	local shine = button:FindFirstChild("Shine", true)
	local gradient = shine and shine:FindFirstChildOfClass("UIGradient")
	local sun = button:FindFirstChild("Sun", true)
	assert(gradient and sun and sun:IsA("GuiObject"), "[BakeryMenu] Next Day needs its authored Shine gradient and Sun")
	local sunRest = sun.Position
	local sweep = TweenService:Create(gradient, NEXT_DAY_SHINE, { Offset = NEXT_DAY_SHINE_TO })
	local bob = TweenService:Create(sun, NEXT_DAY_BOB, { Position = sunRest - UDim2.fromOffset(0, NEXT_DAY_BOB_RISE) })
	local function rest(): ()
		sweep:Cancel()
		bob:Cancel()
		gradient.Offset = NEXT_DAY_SHINE_FROM
		sun.Position = sunRest
	end
	rest()
	janitor:Add(function(): ()
		rest()
		sweep:Destroy()
		bob:Destroy()
	end, true)
	Flux(function(): ()
		if shown() then
			sweep:Play()
			bob:Play()
		else
			rest()
		end
	end, true)
end

return BakeryMenu
