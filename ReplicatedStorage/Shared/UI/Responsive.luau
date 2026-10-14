--!strict
-- Fits a logical page canvas uniformly into the safe viewport. Compact artwork reflows
-- on narrow portrait screens; Animate composes the fit with the page's opening/closing spring.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Animate = require(script.Parent.Animate)
local TextScale = require(script.Parent.TextScale)
local Theme = require(script.Parent.Theme)

--[[ Constants ]]--
local COMPACT_WIDTH = 700
-- The compact artwork is a phone-width layout, not a squeezed desktop canvas.
local COMPACT_CANVAS_WIDTH = 360
local MARGIN = 16
-- A landscape phone's page is height-bound, so it keeps only a sliver above and below; the bakery
-- header rising above its panel still clears Roblox's topbar buttons.
local SHORT_SCREEN_HEIGHT = 500
local SHORT_SCREEN_MARGIN = 8
local SHORT_HEIGHT = 500

--[[ Tables ]]--
local Responsive = {}

--[[ Private Functions ]]--
-- Some authored properties only have a Short or Keyboard override. Leaving that mode restores the
-- geometry recorded before the first override. An attribute survives where a weak table keyed by
-- the instance loses its entry once Luau collects the wrapper.
local function authored(element: GuiObject, property: string, current: UDim2): UDim2?
	if element:GetAttribute(`Short{property}`) == nil and element:GetAttribute(`Keyboard{property}`) == nil then
		return nil
	end
	local recorded = element:GetAttribute(`Authored{property}`)
	if typeof(recorded) == "UDim2" then
		return recorded
	end
	element:SetAttribute(`Authored{property}`, current)
	return current
end

--[[ Handling ]]--
function Responsive.Apply(screen: ScreenGui, viewport: Vector2?): ()
	local panel = screen:FindFirstChild("MainFrame")
	if not panel or not panel:IsA("GuiObject") then
		return
	end
	local available = viewport or screen.AbsoluteSize
	-- Only narrow portrait screens reflow to the compact artwork. Every other screen, phone
	-- landscape included, keeps the desktop canvas and its proportions, scaled like a small window.
	local compact = available.X < COMPACT_WIDTH and available.X < available.Y
	local keyboard = screen.Name == "Codes" and UserInputService.OnScreenKeyboardVisible
	local width = (screen:GetAttribute("PanelWidth") :: number?) or 780
	if compact then
		width = math.min(width, COMPACT_CANVAS_WIDTH)
	end
	local height = (screen:GetAttribute(if compact then "CompactHeight" else "PanelHeight") :: number?) or 680
	if keyboard then
		height = math.min(height, 80)
	end
	width, height = math.max(width, 1), math.max(height, 1)
	local verticalMargin = if available.Y < SHORT_SCREEN_HEIGHT then SHORT_SCREEN_MARGIN else MARGIN
	-- Screen density keeps a short page's share of a phone screen the same as on a desktop.
	local scale = math.min(
		TextScale.Screen(available, Theme.TextScale.Maximum),
		math.max(1, available.X - MARGIN * 2) / width,
		math.max(1, available.Y - verticalMargin * 2) / height
	)
	-- Authored short canvases (Codes) use their Short overrides on every screen.
	local short = height < SHORT_HEIGHT
	panel.Size = UDim2.fromOffset(width, height)
	Animate.SetLayoutScale(panel, scale)
	screen:SetAttribute("Compact", compact)
	screen:SetAttribute("Short", short)
	for _, element in panel:GetDescendants() do
		if element:IsA("UITextSizeConstraint") then
			TextScale.Fit(element, scale)
			continue
		end
		if not element:IsA("GuiObject") then
			continue
		end
		local authoredSize = authored(element, "Size", element.Size)
		local authoredPosition = authored(element, "Position", element.Position)
		local size = (if keyboard then element:GetAttribute("KeyboardSize") else nil)
			or (if short then element:GetAttribute("ShortSize") else nil)
			or element:GetAttribute(if compact then "CompactSize" else "WideSize")
			or authoredSize
		local position = (if keyboard then element:GetAttribute("KeyboardPosition") else nil)
			or (if short then element:GetAttribute("ShortPosition") else nil)
			or element:GetAttribute(if compact then "CompactPosition" else "WidePosition")
			or authoredPosition
		local visible = element:GetAttribute(if compact then "CompactVisible" else "WideVisible")
		if keyboard and element:GetAttribute("KeyboardVisible") ~= nil then
			visible = element:GetAttribute("KeyboardVisible")
		end
		if typeof(size) == "UDim2" then
			element.Size = size
		end
		if typeof(position) == "UDim2" then
			element.Position = position
		end
		if typeof(visible) == "boolean" then
			element.Visible = visible
		end
	end
end

function Responsive.Bind(screen: ScreenGui): any
	local janitor = Janitor.new()
	local function refresh(): ()
		local size = screen.AbsoluteSize
		-- Roblox pans focused text boxes above the native keyboard. Shrink the code
		-- panel as well so its submit button remains beside the focused field.
		if screen.Name == "Codes" and UserInputService.OnScreenKeyboardVisible then
			size = Vector2.new(size.X, math.max(1, size.Y - UserInputService.OnScreenKeyboardSize.Y))
		end
		Responsive.Apply(screen, size)
		local panel = screen:FindFirstChild("MainFrame")
		if screen.Name == "Codes" and panel and panel:IsA("GuiObject") then
			local position = if UserInputService.OnScreenKeyboardVisible
				then UDim2.new(0.5, 0, 0, size.Y / 2)
				else UDim2.fromScale(0.5, 0.5)
			Animate.Place(panel, position)
		end
	end
	janitor:Add(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh), "Disconnect")
	janitor:Add(UserInputService:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Connect(refresh), "Disconnect")
	janitor:Add(UserInputService:GetPropertyChangedSignal("OnScreenKeyboardSize"):Connect(refresh), "Disconnect")
	janitor:LinkToInstance(screen)
	refresh()
	return janitor
end

return Responsive
