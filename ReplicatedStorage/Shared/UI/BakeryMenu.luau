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
local TABS: { [string]: Pages.Page } =
	{ Report = Pages.Names.Report, Menu = Pages.Names.Inventory, Upgrades = Pages.Names.Upgrades }
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
	for name, page in TABS do
		local button = buttons:FindFirstChild(name) :: TextButton
		local available = Flux(function(): boolean
			return (page ~= Pages.Names.Report or phase() == "Summary") and Pages.CanOpen(page)
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
		Visible = function(): boolean
			return phase() == "Summary"
		end,
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
