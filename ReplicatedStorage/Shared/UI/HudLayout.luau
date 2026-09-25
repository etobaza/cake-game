--!strict
-- The HUD's resting rectangles. Motion reads HomePosition, so a viewport change
-- updates the destination without fighting the spring that currently draws it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local OrderLayout = require(script.Parent.OrderLayout)

--[[ Constants ]]--
-- Desktop artwork was sized for a 720p canvas. Keep that density on larger
-- displays, bounded by both axes so narrow windows cannot push groups together.
local DESKTOP_CANVAS = Vector2.new(1280, 720)
local MAX_DESKTOP_SCALE = 2
-- Separate the earned-XP toast from quests and the phone's right-hand controls.
local XP_GAP = 16
local LANDSCAPE_TOUCH_INSET = 132

--[[ Tables ]]--
local HudLayout = {}

--[[ Private Functions ]]--
local function place(hud: Instance, name: string, position: UDim2, size: Vector2, scale: number): ()
	local group = hud:FindFirstChild(name)
	if not group or not group:IsA("GuiObject") then
		return
	end
	group.Size = UDim2.fromOffset(size.X * scale, size.Y * scale)
	group:SetAttribute(
		"HomePosition",
		UDim2.new(position.X.Scale, position.X.Offset * scale, position.Y.Scale, position.Y.Offset * scale)
	)
end

--[[ Handling ]]--
function HudLayout.Apply(hud: GuiObject): ()
	local size = hud.AbsoluteSize
	local compact = size.X < 700 or size.Y < 500
	local portrait = size.Y > size.X
	local scale = if compact
		then 1
		else math.clamp(math.min(size.X / DESKTOP_CANVAS.X, size.Y / DESKTOP_CANVAS.Y), 1, MAX_DESKTOP_SCALE)
	local buttonSide = if compact then math.clamp(math.floor((size.Y - 108) / 3), 52, 64) else 100
	local columnHeight = buttonSide * 3 + 16
	-- Resize the resting rectangles; UIScale remains owned by press/pop springs.
	local function placeGroup(name: string, position: UDim2, dimensions: Vector2): ()
		place(hud, name, position, dimensions, scale)
	end
	local anchors: { [string]: Vector2 } = {
		Time = Vector2.new(0.5, 0.5),
		Hotbar = Vector2.new(0.5, 1),
		XP = Vector2.new(1, 0),
		Currency = Vector2.new(0, if compact then 0 else 1),
		SideBtns = Vector2.new(0, 0.5),
		Order = Vector2.new(1, 1),
		Quests = Vector2.new(1, 0.5),
	}
	for name, anchor in anchors do
		local group = hud:FindFirstChild(name)
		if group and group:IsA("GuiObject") then
			group.AnchorPoint = anchor
		end
	end
	placeGroup(
		"Time",
		UDim2.new(0.5, 0, 0, if compact then 16 else 23),
		Vector2.new(144, 51) * (if compact then 1 else 1.25)
	)
	placeGroup("Hotbar", UDim2.new(0.5, 0, 1, -12), if compact then Vector2.new(76, 68) else Vector2.new(96, 86))
	if compact then
		placeGroup("Currency", UDim2.fromOffset(8, if portrait then 78 else 8), Vector2.new(150, 70))
		-- The landscape column starts below the currency plate (bottom at 78).
		placeGroup(
			"SideBtns",
			if portrait then UDim2.new(0, 8, 0.5, 0) else UDim2.fromOffset(8, 84 + columnHeight / 2),
			Vector2.new(buttonSide + 4, columnHeight)
		)
		placeGroup(
			"Quests",
			if portrait then UDim2.new(1, -8, 0.5, 30) else UDim2.new(1, -8, 0, 100),
			if portrait then Vector2.new(220, 150) else Vector2.new(184, 120)
		)
	else
		placeGroup("Currency", UDim2.new(0, 16, 1, -16), Vector2.new(250, 112))
		placeGroup("SideBtns", UDim2.new(0, 16, 0.5, 0), Vector2.new(108, 348))
		placeGroup("Quests", UDim2.new(1, -16, 0.5, 0), Vector2.new(300, 190))
	end
	OrderLayout.Apply(hud, compact, scale)
	local quests = hud:FindFirstChild("Quests")
	if quests and quests:IsA("GuiObject") then
		local arrow = quests:FindFirstChild("Btn")
		local container = quests:FindFirstChild("Container")
		if arrow and arrow:IsA("GuiObject") then
			arrow.AnchorPoint = Vector2.new(0, 0.5)
			arrow.Position = UDim2.fromScale(0, 0.5)
			arrow.Size = UDim2.fromOffset(44 * scale, 44 * scale)
		end
		if container and container:IsA("GuiObject") then
			container.Position = UDim2.fromOffset(60 * scale, 0)
			container.Size = UDim2.new(1, -60 * scale, 1, 0)
		end
		local questHome = quests:GetAttribute("HomePosition") :: UDim2
		local rightInset = if compact and not portrait then LANDSCAPE_TOUCH_INSET else (if compact then 8 else 16)
		local top = questHome.Y.Offset + quests.Size.Y.Offset * (1 - quests.AnchorPoint.Y) + XP_GAP * scale
		-- These coordinates are already scaled; the slide spring reads the same resting point.
		place(hud, "XP", UDim2.new(1, -rightInset * scale, questHome.Y.Scale, top), Vector2.new(200, 44) * scale, 1)
	end
	local buttons = hud:FindFirstChild("SideBtns")
	if buttons then
		local layout = buttons:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.Padding = UDim.new(0, 8 * scale)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
		end
		local buttonSize = buttonSide * scale
		for _, button in buttons:GetChildren() do
			if not button:IsA("GuiObject") then
				continue
			end
			button.Size = UDim2.fromOffset(buttonSize, buttonSize)
			local title = button:FindFirstChild(if button.Name == "Rewards" then "Title" else button.Name)
			if title and title:IsA("GuiObject") then
				title.AnchorPoint = Vector2.new(0.5, 0)
				title.Position = UDim2.fromScale(0.5, 0.77)
				title.Size = UDim2.fromScale(1, 0.25)
			end
			local hitbox = button:FindFirstChild("Btn")
			if hitbox and hitbox:IsA("GuiObject") then
				hitbox.AnchorPoint = Vector2.new(0.5, 0.5)
				hitbox.Position = UDim2.fromScale(0.5, 0.5)
				hitbox.Size = UDim2.fromScale(1, 1)
			end
		end
	end
end

function HudLayout.Bind(hud: GuiObject): any
	local janitor = Janitor.new()
	local orders = hud:FindFirstChild("Order")
	if orders then
		janitor:Add(orders:GetAttributeChangedSignal("OrderCount"):Connect(function(): ()
			HudLayout.Apply(hud)
		end), "Disconnect")
	end
	janitor:Add(
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function(): ()
			HudLayout.Apply(hud)
		end),
		"Disconnect"
	)
	janitor:LinkToInstance(hud)
	HudLayout.Apply(hud)
	return janitor
end

return HudLayout
