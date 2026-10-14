--!strict
-- One authored header stays in place while the bakery's report, menu and upgrades switch.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--[[ Modules ]]--
local Animate = require(script.Parent.Animate)
local ButtonRow = require(script.Parent.ButtonRow)
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(script.Parent.Stores.Pages)
local UseData = require(script.Parent.Hooks.UseData)

--[[ Constants ]]--
local TABS: { [string]: Pages.Page } = {
	Report = Pages.Names.Report,
	Menu = Pages.Names.Inventory,
}
local TAB_BUTTONS = { "Report", "Menu" }
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
			return not isSummary()
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
		Visible = isSummary,
		Position = rowPosition,
		Size = rowSize,
	})
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
	for name, page in TABS do
		local button = buttons:FindFirstChild(name) :: TextButton
		local available = Flux(function(): boolean
			return isSummary() and Pages.CanOpen(page)
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
	bindPress(close)
	Flux.edit(close)({
		Visible = function(): boolean
			return not Pages.Locked()
		end,
		Activated = function(): ()
			Pages.Close()
		end,
	})
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
