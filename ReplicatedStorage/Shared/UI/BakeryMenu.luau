--!strict
-- One authored header stays in place while the bakery's report, menu and upgrades switch.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Animate = require(script.Parent.Animate)
local ButtonRow = require(script.Parent.ButtonRow)
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(script.Parent.Stores.Pages)
local UseData = require(script.Parent.Hooks.UseData)

--[[ Constants ]]--
local TABS: { [string]: Pages.Page } = { Report = Pages.Names.Report, Menu = Pages.Names.Inventory }
local HEADER_BUTTONS = { "Report", "Menu", "NextDay" }
local HEADER_LEFT_INSET = 6
local HEADER_RIGHT_INSET = 6
local HEADER_GAP = 8
local HEADER_Y = -22
local RIBBON_OVERHANG = 64
local SELECTED = Color3.fromRGB(247, 233, 205)
local IDLE = Color3.fromRGB(205, 191, 161)
local DISABLED = Color3.fromRGB(150, 143, 127)

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
			return BakeryMenu.Contains(Pages.Current())
		end,
	})
	-- Standalone pages use the full-size authored ribbon title, not a small tab caption.
	local upgrades = buttons:FindFirstChild("Upgrades") :: TextButton
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
	Flux.edit(upgrades)({ Visible = false, Interactable = false, Selectable = false })
	local rowButtons: { GuiObject } = {}
	for index, name in HEADER_BUTTONS do
		local button = buttons:FindFirstChild(name) :: TextButton
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale((index - 0.5) / #HEADER_BUTTONS, 0.5)
		button.Size = UDim2.new(1 / #HEADER_BUTTONS, -HEADER_GAP, 1, 0)
		local lines = button:FindFirstChild("Lines") :: ImageLabel
		lines.AnchorPoint = Vector2.new(0.5, 0.5)
		lines.Position = UDim2.fromScale(0.5, 0.5)
		table.insert(rowButtons, button)
	end
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
	local nextDay = buttons:FindFirstChild("NextDay") :: TextButton
	Flux.edit(nextDay)({
		Visible = isSummary,
	})
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

return BakeryMenu
