--!strict
-- Fits a logical page canvas uniformly into the safe viewport. Compact artwork reflows
-- on narrow screens; Animate composes the fit with the page's opening/closing spring.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Animate = require(script.Parent.Animate)

--[[ Constants ]]--
local COMPACT_WIDTH = 700
-- The compact artwork is a phone-width layout, not a squeezed desktop canvas.
local COMPACT_CANVAS_WIDTH = 360
local MARGIN = 16

--[[ Private Variables ]]--
-- Some authored properties only have a Short override. Restore their original geometry
-- when leaving that mode, rather than retaining the previous viewport's override.
local Originals: { [GuiObject]: { Size: UDim2, Position: UDim2 } } = setmetatable({}, { __mode = "k" }) :: any

--[[ Tables ]]--
local Responsive = {}

--[[ Private Functions ]]--
local function fitText(constraint: UITextSizeConstraint, scale: number): ()
	-- Constraints clamp rendered pixels after UIScale. An authored 22px minimum
	-- must not force a 10px-high phone label to render oversized text.
	-- The baseline travels with cloned rows, so later reflows never scale it twice.
	local authored = constraint:GetAttribute("AuthoredMaxTextSize")
	local maximum: number
	if typeof(authored) == "number" then
		maximum = authored
	else
		maximum = constraint.MaxTextSize
		constraint:SetAttribute("AuthoredMaxTextSize", maximum)
	end
	constraint.MinTextSize = 1
	constraint.MaxTextSize = math.max(1, math.floor(maximum * scale + 0.5))
end

--[[ Handling ]]--
function Responsive.Apply(screen: ScreenGui, viewport: Vector2?): ()
	local panel = screen:FindFirstChild("MainFrame")
	if not panel or not panel:IsA("GuiObject") then
		return
	end
	local available = viewport or screen.AbsoluteSize
	local compact = available.X < COMPACT_WIDTH
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
	-- Both axes use the same factor: a short phone must not flatten the page's artwork.
	local scale =
		math.min(1, math.max(1, available.X - MARGIN * 2) / width, math.max(1, available.Y - MARGIN * 2) / height)
	local short = height < 500
	panel.Size = UDim2.fromOffset(width, height)
	Animate.SetLayoutScale(panel, scale)
	screen:SetAttribute("Compact", compact)
	screen:SetAttribute("Short", short)
	for _, element in panel:GetDescendants() do
		if element:IsA("UITextSizeConstraint") then
			fitText(element, scale)
			continue
		end
		if not element:IsA("GuiObject") then
			continue
		end
		local original = Originals[element]
		if not original then
			original = { Size = element.Size, Position = element.Position }
			Originals[element] = original
		end
		local size = (if keyboard then element:GetAttribute("KeyboardSize") else nil)
			or (if short then element:GetAttribute("ShortSize") else nil)
			or element:GetAttribute(if compact then "CompactSize" else "WideSize")
		local position = (if keyboard then element:GetAttribute("KeyboardPosition") else nil)
			or (if short then element:GetAttribute("ShortPosition") else nil)
			or element:GetAttribute(if compact then "CompactPosition" else "WidePosition")
		local visible = element:GetAttribute(if compact then "CompactVisible" else "WideVisible")
		if keyboard and element:GetAttribute("KeyboardVisible") ~= nil then
			visible = element:GetAttribute("KeyboardVisible")
		end
		if not size and (element:GetAttribute("ShortSize") or element:GetAttribute("KeyboardSize")) then
			size = original.Size
		end
		if not position and (element:GetAttribute("ShortPosition") or element:GetAttribute("KeyboardPosition")) then
			position = original.Position
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
