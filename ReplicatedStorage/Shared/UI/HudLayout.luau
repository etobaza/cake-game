--!strict
-- The HUD's resting rectangles. Motion reads HomePosition, so a viewport change
-- updates the destination without fighting the spring that currently draws it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local HudConfig = require(ReplicatedStorage.Shared.Configs.HudLayout)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local OrderLayout = require(script.Parent.OrderLayout)
local TextScale = require(script.Parent.TextScale)
local Theme = require(script.Parent.Theme)
local UpgradeReveal = require(ReplicatedStorage.Shared.Configs.UpgradeReveal)

--[[ Constants ]]--
-- Logical sizes and offsets below were drawn for a 720p canvas; every arrangement draws them at
-- HudLayout.Scale, so each group keeps about the same share of the screen on phones and desktops.
local EDGE = 16
local TIME_SIZE = Vector2.new(180, 64)
local CURRENCY_SIZE = Vector2.new(250, 112)
local QUESTS_SIZE = Vector2.new(300, 190)
local BUTTON_SIDE = 100
local BUTTON_GAP = 8
local QUEST_ARROW = 44
local XP_SIZE = Vector2.new(200, 44)
local HOTBAR_SIZE = Vector2.new(128, 126)
local HOTBAR_BOTTOM = 12
-- Separate the earned-XP toast from quests and the touch controls.
local XP_GAP = 16
-- RunControl's published bottom-right area of the live touch jump/run controls.
local TOUCH_RESERVE = "TouchReserve"

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

local function runButton(hud: Instance): Instance?
	local controls = hud:FindFirstChild("Controls")
	return controls and controls:FindFirstChild("Run")
end

local function touchReserve(hud: Instance): Vector2?
	local run = runButton(hud)
	local reserve = run and run:GetAttribute(TOUCH_RESERVE)
	return if typeof(reserve) == "Vector2" then reserve else nil
end

--[[ Handling ]]--
--- The HUD's density at `viewport`: the shared screen density, growing on large desktops.
function HudLayout.Scale(viewport: Vector2): number
	return TextScale.Screen(viewport, HudConfig.MaxScale)
end

--- A configured HUD text size at `scale`, never below the HUD's legibility floor.
function HudLayout.TextSize(size: number, scale: number): number
	return math.max(TextScale.Size(size, scale), Theme.ScreenScale.MinTextPixels)
end

function HudLayout.Apply(hud: GuiObject): ()
	local size = hud.AbsoluteSize
	local compact = size.X < HudConfig.CompactWidth or size.Y < HudConfig.CompactHeight
	local portrait = size.Y > size.X
	local scale = HudLayout.Scale(size)
	local logical = size / scale
	local reserve = touchReserve(hud)
	local hotbarLeft = (logical.X - HOTBAR_SIZE.X) / 2
	-- The touch movement stick holds the bottom-left corner, so there the plate docks beside the hotbar.
	local currencyLeft = if reserve then math.max(EDGE, hotbarLeft - EDGE - CURRENCY_SIZE.X) else EDGE
	-- A screen too narrow for the plate beside the hotbar lifts the plate above it.
	local currencyBottom = if currencyLeft + CURRENCY_SIZE.X > hotbarLeft
		then HOTBAR_BOTTOM + HOTBAR_SIZE.Y + BUTTON_GAP
		else EDGE
	-- The button column fits between the top edge and the plate, or the stick in its place; short
	-- screens shrink its buttons.
	local columnRoom = logical.Y - currencyBottom - CURRENCY_SIZE.Y - EDGE * 2
	local fit = (columnRoom - BUTTON_GAP * 2) / (UpgradeReveal.Hud.SizeMultiplier + 2)
	local buttonSide = math.min(BUTTON_SIDE, math.max(fit, Theme.ScreenScale.MinTouchPixels / scale))
	local upgradeSide = buttonSide * UpgradeReveal.Hud.SizeMultiplier
	local columnHeight = upgradeSide + buttonSide * 2 + BUTTON_GAP * 2
	local columnCentre = math.min(logical.Y / 2, EDGE + columnRoom - columnHeight / 2)
	-- Resize the resting rectangles; UIScale remains owned by press/pop springs.
	local function placeGroup(name: string, position: UDim2, dimensions: Vector2): ()
		place(hud, name, position, dimensions, scale)
	end
	local anchors: { [string]: Vector2 } = {
		Time = Vector2.new(0.5, 0.5),
		Hotbar = Vector2.new(0.5, 1),
		XP = Vector2.new(1, 0),
		Currency = Vector2.new(0, 1),
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
	-- The clock doubles as the Open button, so it keeps a usable touch height.
	place(hud, "Time", UDim2.new(0.5, 0, 0, 23), TIME_SIZE, math.max(scale, Theme.ScreenScale.MinTouchPixels / TIME_SIZE.Y))
	placeGroup("Hotbar", UDim2.new(0.5, 0, 1, -HOTBAR_BOTTOM), HOTBAR_SIZE)
	placeGroup("Currency", UDim2.new(0, currencyLeft, 1, -currencyBottom), CURRENCY_SIZE)
	placeGroup("SideBtns", UDim2.fromOffset(EDGE, columnCentre), Vector2.new(upgradeSide + 8, columnHeight))
	if compact then
		placeGroup(
			"Quests",
			if portrait then UDim2.new(1, -EDGE, 0.5, 50) else UDim2.new(1, -EDGE, 0, EDGE + QUESTS_SIZE.Y / 2),
			QUESTS_SIZE
		)
	else
		placeGroup("Quests", UDim2.new(1, -EDGE, 0.5, 0), QUESTS_SIZE)
	end
	OrderLayout.Apply(hud, scale, reserve)
	local quests = hud:FindFirstChild("Quests")
	if quests and quests:IsA("GuiObject") then
		local arrow = quests:FindFirstChild("Btn")
		local container = quests:FindFirstChild("Container")
		local arrowSide = math.max(QUEST_ARROW * scale, Theme.ScreenScale.MinTouchPixels)
		if arrow and arrow:IsA("GuiObject") then
			arrow.AnchorPoint = Vector2.new(0, 0.5)
			arrow.Position = UDim2.fromScale(0, 0.5)
			arrow.Size = UDim2.fromOffset(arrowSide, arrowSide)
		end
		if container and container:IsA("GuiObject") then
			container.Position = UDim2.fromOffset(arrowSide + 16 * scale, 0)
			container.Size = UDim2.new(1, -arrowSide - 16 * scale, 1, 0)
		end
		local questHome = quests:GetAttribute("HomePosition") :: UDim2
		local xpSize = XP_SIZE * scale
		local top = questHome.Y.Offset + quests.Size.Y.Offset * (1 - quests.AnchorPoint.Y) + XP_GAP * scale
		local right = EDGE * scale
		if reserve and size.Y * questHome.Y.Scale + top + xpSize.Y > size.Y - reserve.Y then
			right = math.max(right, reserve.X + XP_GAP * scale)
		end
		-- These coordinates are already scaled; the slide spring reads the same resting point.
		place(hud, "XP", UDim2.new(1, -right, questHome.Y.Scale, top), xpSize, 1)
		local xp = hud:FindFirstChild("XP")
		local plus = xp and xp:FindFirstChild("Plus")
		local plusHitbox = plus and plus:FindFirstChild("Btn")
		if plus and plus:IsA("GuiObject") and plusHitbox and plusHitbox:IsA("GuiObject") then
			-- The plus is a fixed share of the toast; small screens pad its hitbox to a touch target.
			local drawn = Vector2.new(plus.Size.X.Scale * xpSize.X, plus.Size.Y.Scale * xpSize.Y)
			local pad = (Vector2.one * Theme.ScreenScale.MinTouchPixels - drawn):Max(Vector2.zero)
			plusHitbox.Size = UDim2.new(1, pad.X, 1, pad.Y)
		end
	end
	local buttons = hud:FindFirstChild("SideBtns")
	if buttons then
		local layout = buttons:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, BUTTON_GAP * scale)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
		end
		local buttonSize = buttonSide * scale
		for _, button in buttons:GetChildren() do
			if not button:IsA("GuiObject") then
				continue
			end
			local side = if button.Name == "Upgrades" then upgradeSide * scale else buttonSize
			button.Size = UDim2.fromOffset(side, side)
			button.LayoutOrder = if button.Name == "Upgrades" then 1 elseif button.Name == "Shop" then 2 else 3
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
				hitbox.SelectionOrder = button.LayoutOrder
			end
		end
	end
end

function HudLayout.Bind(hud: GuiObject): any
	local janitor = Janitor.new()
	local function apply(): ()
		HudLayout.Apply(hud)
	end
	local orders = hud:FindFirstChild("Order")
	if orders then
		janitor:Add(orders:GetAttributeChangedSignal("OrderCount"):Connect(apply), "Disconnect")
	end
	local run = runButton(hud)
	if run then
		janitor:Add(run:GetAttributeChangedSignal(TOUCH_RESERVE):Connect(apply), "Disconnect")
	end
	janitor:Add(hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply), "Disconnect")
	janitor:LinkToInstance(hud)
	HudLayout.Apply(hud)
	return janitor
end

return HudLayout
