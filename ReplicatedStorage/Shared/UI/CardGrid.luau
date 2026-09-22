--!strict
-- Resizes an authored grid without rebuilding its cards. Hidden cells do not occupy
-- canvas space; filtering and viewport changes both update the existing layout.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Authored = require(script.Parent.Authored)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Constants ]]--
local GAP = 12
local PADDING = 8

--[[ Tables ]]--
local CardGrid = {}

--[[ Handling ]]--
function CardGrid.Bind(holder: GuiObject): any
	local janitor = Janitor.new()
	local layout = holder:FindFirstChildOfClass("UIGridLayout")
	if not layout then
		return janitor
	end
	local screen = holder:FindFirstAncestorWhichIsA("ScreenGui")
	local function refresh(): ()
		local compact = screen ~= nil and screen:GetAttribute("Compact") == true
		local short = screen ~= nil and screen:GetAttribute("Short") == true
		local function number(name: string): number?
			return holder:GetAttribute(name) :: number?
		end
		local columns = number(if compact then "CompactColumns" else "WideColumns") or 5
		if short then
			columns = number("ShortColumns") or columns
		end
		local width = math.max(1, Authored.UnscaledSize(holder).X - PADDING * 2 - 8)
		local cellWidth = math.floor((width - GAP * (columns - 1)) / columns)
		local height = (if short then number("ShortCellHeight") else nil) or number("CellHeight") or 142
		layout.CellSize = UDim2.fromOffset(math.max(1, cellWidth), height)
	end
	janitor:Add(holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh), "Disconnect")
	if screen then
		janitor:Add(screen:GetAttributeChangedSignal("Compact"):Connect(refresh), "Disconnect")
	end
	if screen then
		janitor:Add(screen:GetAttributeChangedSignal("Short"):Connect(refresh), "Disconnect")
	end
	janitor:LinkToInstance(holder)
	refresh()
	return janitor
end

return CardGrid
