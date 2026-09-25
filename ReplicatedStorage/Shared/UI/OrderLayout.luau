--!strict
-- Fits the authored order ribbon to its visible cards and keeps it clear of the hotbar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.Orders)

local OrderLayout = {}

function OrderLayout.Apply(hud: GuiObject, compact: boolean, hudScale: number): ()
	local root = hud:FindFirstChild("Order")
	local hotbar = hud:FindFirstChild("Hotbar")
	if not root or not root:IsA("GuiObject") or not hotbar or not hotbar:IsA("GuiObject") then
		return
	end

	local config = Config.Layout
	local layout = if compact then config.Compact else config.Wide
	local scale = math.min(hudScale, config.MaxScale)
	local count = math.clamp((root:GetAttribute("OrderCount") :: number?) or 1, 1, Config.Slots)
	local edge = layout.Edge * scale
	local desiredWidth = (count * layout.CardWidth + layout.LabelWidth) * scale
	local width = math.min(desiredWidth, math.max(1, hud.AbsoluteSize.X - edge * 2))
	local height = layout.Height * scale
	local gap = config.HotbarGap * scale
	local hotbarHome = (hotbar:GetAttribute("HomePosition") :: UDim2?) or hotbar.Position
	local hotbarRight = hud.AbsoluteSize.X * hotbarHome.X.Scale + hotbarHome.X.Offset
		+ hotbar.Size.X.Offset * (1 - hotbar.AnchorPoint.X)
	local bottom = edge
	-- A full row moves above the centered hotbar instead of crossing it.
	if hud.AbsoluteSize.X - edge - width < hotbarRight + gap then
		bottom = math.max(bottom, -hotbarHome.Y.Offset + hotbar.Size.Y.Offset + gap)
	end
	local availableWidth = width
	for _, name in { "SideBtns", "Currency" } do
		local group = hud:FindFirstChild(name)
		if not group or not group:IsA("GuiObject") then
			continue
		end
		local home = (group:GetAttribute("HomePosition") :: UDim2?) or group.Position
		local top = hud.AbsoluteSize.Y * home.Y.Scale + home.Y.Offset - group.Size.Y.Offset * group.AnchorPoint.Y
		local orderBottom = hud.AbsoluteSize.Y - bottom
		if orderBottom > top and orderBottom - height < top + group.Size.Y.Offset then
			local right = hud.AbsoluteSize.X * home.X.Scale + home.X.Offset
				+ group.Size.X.Offset * (1 - group.AnchorPoint.X)
			availableWidth = math.min(availableWidth, math.max(1, hud.AbsoluteSize.X - edge - right - gap))
		end
	end
	-- Short portrait screens can share a row with the side buttons. Keep usable
	-- card widths there by scrolling fewer slots, rather than squeezing four cards.
	local slots = math.clamp(math.floor((availableWidth / scale - layout.LabelWidth) / layout.CardWidth), 1, count)
	width = math.min(availableWidth, (slots * layout.CardWidth + layout.LabelWidth) * scale)

	root.AnchorPoint = Vector2.one
	root.Size = UDim2.fromOffset(width, height)
	root:SetAttribute("VisibleOrderSlots", slots)
	root:SetAttribute("HomePosition", UDim2.new(1, -edge, 1, -bottom))

	local labelWidth = math.min(layout.LabelWidth * scale, width / 2)
	local container = root:FindFirstChild("Container")
	if container and container:IsA("GuiObject") then
		container.AnchorPoint = Vector2.zero
		container.Position = UDim2.fromScale(0, 0)
		container.Size = UDim2.new(1, -labelWidth, 1, 0)
	end
	local background = root:FindFirstChild("Background")
	if background and background:IsA("GuiObject") then
		background.AnchorPoint = Vector2.new(0, 0.5)
		background.Position = UDim2.fromScale(0, 0.55)
		background.Size = UDim2.fromScale(1, 0.31)
	end
	local label = root:FindFirstChild("Order")
	if label and label:IsA("GuiObject") then
		label.AnchorPoint = Vector2.new(1, 0.5)
		label.Position = UDim2.fromScale(1, 0.55)
		label.Size = UDim2.new(0, labelWidth, 0.16, 0)
	end
end

return OrderLayout
