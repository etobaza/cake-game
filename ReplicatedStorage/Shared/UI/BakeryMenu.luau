--!strict
-- One authored header stays in place while the bakery's report, menu and upgrades switch.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Animate = require(script.Parent.Animate)
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(script.Parent.Stores.Pages)
local UseData = require(script.Parent.Hooks.UseData)

--[[ Constants ]]--
local TABS: { [string]: Pages.Page } = { Report = Pages.Names.Report, Menu = Pages.Names.Inventory }
local HEADER_BUTTONS = { "Report", "Menu", "NextDay" }
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
		-- Next Day hides both itself and the screen while the pointer is still over it.
		-- MouseLeave is not guaranteed on hidden UI, so each visibility cycle starts at rest.
		janitor:Add(screen:GetPropertyChangedSignal("Enabled"):Connect(reset), "Disconnect")
		janitor:Add(button:GetPropertyChangedSignal("Visible"):Connect(reset), "Disconnect")
		janitor:Add(button:GetPropertyChangedSignal("Interactable"):Connect(reset), "Disconnect")
	end
	Flux.edit(screen)({
		Enabled = function(): boolean
			return BakeryMenu.Contains(Pages.Current())
		end,
	})
	-- Standalone HUD pages borrow the authored white text without the evening tab artwork.
	local upgrades = buttons:FindFirstChild("Upgrades") :: TextButton
	local title = (upgrades:FindFirstChild("Txt") :: Frame):Clone()
	title.Name = "Title"
	title.AnchorPoint = buttons.AnchorPoint
	title.Position = buttons.Position
	title.Size = buttons.Size
	title.Parent = header
	janitor:Add(title, "Destroy")
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
	-- Evening navigation has no close button, so use matching insets on both sides.
	Flux.edit(buttons)({
		Visible = isSummary,
		Size = UDim2.new(1, -2 * buttons.Position.X.Offset, buttons.Size.Y.Scale, buttons.Size.Y.Offset),
	})
	Flux.edit(upgrades)({ Visible = false, Interactable = false, Selectable = false })
	for index, name in HEADER_BUTTONS do
		local button = buttons:FindFirstChild(name) :: TextButton
		button.Position = UDim2.fromScale((index - 0.5) / #HEADER_BUTTONS, 0.5)
		button.Size = UDim2.new(1 / #HEADER_BUTTONS, -8, 1, 0)
	end
	for name, page in TABS do
		local button = buttons:FindFirstChild(name) :: TextButton
		local available = Flux(function(): boolean
			return isSummary() and Pages.CanOpen(page)
		end)
		bindPress(button)
		Flux.edit(button)({
			Interactable = available,
			Selectable = available,
			Activated = function(): ()
				if available:peek() then
					Pages.Open(page)
				end
			end,
		})
		Flux.edit(button:FindFirstChild("Bg") :: Frame)({
			BackgroundColor3 = function(): Color3
				return if not available() then DISABLED else if Pages.Current() == page then SELECTED else IDLE
			end,
		})
	end
	local nextDay = buttons:FindFirstChild("NextDay") :: TextButton
	bindPress(nextDay)
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
