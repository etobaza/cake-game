--!strict
-- One guest's speech bubble: the ordered dishes, their names, the seat number and the patience left.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Config = require(_Shared.Configs.Orders)
local FoodPreview = require(_Shared.UI.FoodPreview)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local Theme = require(_Shared.UI.Theme)

--[[ Constants ]]--
local STYLE = Config.Bubble

--[[ Types ]]--
export type View = {
	State: string,
	Orders: { string },
	Seat: string?,
	-- Share of patience left, 0-1.
	Remaining: number,
	Now: number,
}

--[[ Tables ]]--
local Bubble = {}
Bubble.__index = Bubble

export type Bubble = typeof(setmetatable(
	{} :: {
		Model: Model,
		Janitor: any,
		Panel: Frame,
		Icons: { ImageLabel },
		Ponder: TextLabel,
		Caption: TextLabel,
		Badge: Frame,
		BadgeText: TextLabel,
		Clip: Frame,
		Fill: Frame,
		Gradient: UIGradient?,
		-- The order HUD's own fill colours, restored once patience recovers (a placed order).
		Calm: ColorSequence?,
		Key: string,
		State: string,
		Low: boolean,
		NextWobbleAt: number,
	},
	Bubble
))

--[[ Private Functions ]]--
local function round(parent: GuiObject, radius: UDim): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function outline(parent: GuiObject): ()
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelEdge
	stroke.Thickness = STYLE.StrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

local function label(name: string, parent: GuiObject, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = Theme.Fonts.Bold
	text.TextColor3 = Theme.Colors.Cocoa
	text.TextScaled = true
	text.TextWrapped = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.Parent = text
	text.Parent = parent
	return text
end

local function height(): number
	return STYLE.Padding * 4 + STYLE.IconSize + STYLE.CaptionHeight + STYLE.BarHeight
end

--[[ Handling ]]--
function Bubble.new(model: Model, head: BasePart, barTemplate: CanvasGroup): Bubble
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OrderBubble"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(STYLE.Width, height() + STYLE.TailSize)
	-- Grow upward from the anchor, so a taller bubble never sinks into the guest's head.
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.StudsOffsetWorldSpace = STYLE.Offset
	billboard.MaxDistance = STYLE.MaxDistance
	-- AlwaysOnTop billboards do not draw ViewportFrames or CanvasGroups: the dish preview and the
	-- patience bar would both vanish.
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Global

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0, height() / 2)
	panel.Size = UDim2.fromOffset(STYLE.Width - STYLE.StrokeThickness * 2, height())
	panel.BackgroundColor3 = Theme.Colors.PanelFill
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = billboard
	round(panel, UDim.new(0, STYLE.CornerRadius))
	outline(panel)

	-- A rotated square half hidden behind the panel points the bubble at the guest.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 1)
	tail.Size = UDim2.fromOffset(STYLE.TailSize * 1.4, STYLE.TailSize * 1.4)
	tail.Rotation = 45
	tail.BackgroundColor3 = Theme.Colors.PanelFill
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	tail.Parent = panel
	outline(tail)
	-- Covers the tail's stroke where it crosses into the panel.
	local seam = Instance.new("Frame")
	seam.Name = "Seam"
	seam.AnchorPoint = Vector2.new(0.5, 1)
	seam.Position = UDim2.new(0.5, 0, 1, STYLE.StrokeThickness + 0.5)
	seam.Size = UDim2.fromOffset(STYLE.TailSize * 1.2, STYLE.TailSize)
	seam.BackgroundColor3 = Theme.Colors.PanelFill
	seam.BorderSizePixel = 0
	seam.ZIndex = 3
	seam.Parent = panel

	local row = Instance.new("Frame")
	row.Name = "Dishes"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, STYLE.Padding)
	row.Size = UDim2.new(1, 0, 0, STYLE.IconSize)
	row.ZIndex = 4
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, STYLE.IconGap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local icons: { ImageLabel } = {}
	for index = 1, STYLE.MaxIcons do
		local icon = Instance.new("ImageLabel")
		icon.Name = `Dish{index}`
		icon.LayoutOrder = index
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(STYLE.IconSize, STYLE.IconSize)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Visible = false
		icon.ZIndex = 4
		icon.Parent = row
		icons[index] = icon
	end

	local ponder = label("Ponder", panel, STYLE.PonderSize)
	ponder.Position = row.Position
	ponder.Size = row.Size
	ponder.FontFace = Theme.Fonts.ExtraBold
	ponder.ZIndex = 4

	local caption = label("Caption", panel, STYLE.TextSize)
	caption.Position = UDim2.fromOffset(STYLE.Padding, STYLE.Padding * 2 + STYLE.IconSize)
	caption.Size = UDim2.new(1, -STYLE.Padding * 2, 0, STYLE.CaptionHeight)
	caption.ZIndex = 4

	-- Preserve the order HUD's exact border, mask and striped artwork.
	local bar = barTemplate:Clone()
	bar.Name = "Patience"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, STYLE.Padding, 1, -STYLE.Padding)
	bar.Size = UDim2.new(1, -STYLE.Padding * 2, 0, STYLE.BarHeight)
	bar.Visible = true
	bar.GroupTransparency = 0
	bar.ZIndex = 4
	bar.Parent = panel
	local clip = bar:FindFirstChild("Clip")
	local fill = clip and clip:FindFirstChild("Fill")
	assert(clip and clip:IsA("Frame"), "[GuestOrderHandler] Order bar has no Clip frame")
	assert(fill and fill:IsA("Frame"), "[GuestOrderHandler] Order bar has no Clip.Fill frame")
	local gradient = fill:FindFirstChildOfClass("UIGradient")

	local badge = Instance.new("Frame")
	badge.Name = "Seat"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(STYLE.BadgeSize / 3, STYLE.BadgeSize / 3)
	badge.Size = UDim2.fromOffset(STYLE.BadgeSize * 1.4, STYLE.BadgeSize)
	badge.BackgroundColor3 = Theme.Colors.Cocoa
	badge.BorderSizePixel = 0
	badge.ZIndex = 5
	badge.Parent = panel
	round(badge, Theme.Corners.Pill)
	local badgeText = label("Number", badge, STYLE.BadgeTextSize)
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.TextColor3 = Theme.Colors.TextFace
	badgeText.ZIndex = 6

	local self: Bubble = setmetatable({
		Model = model,
		Janitor = Janitor.new(),
		Panel = panel,
		Icons = icons,
		Ponder = ponder,
		Caption = caption,
		Badge = badge,
		BadgeText = badgeText,
		Clip = clip,
		Fill = fill,
		Gradient = gradient,
		Calm = if gradient then gradient.Color else nil,
		Key = "",
		State = "",
		Low = false,
		NextWobbleAt = 0,
	}, Bubble)
	self.Janitor:Add(function(): ()
		for _, icon in icons do
			FoodPreview.Clear(icon)
		end
	end, true)
	self.Janitor:Add(billboard, "Destroy")
	billboard.Parent = model
	Animate.Pop(panel, Config.Pop.Appear)
	return self
end

function Bubble.SetRemaining(self: Bubble, remaining: number, now: number): ()
	local ratio = math.clamp(remaining, 0, 1)
	self.Clip.Size = UDim2.fromScale(ratio, 1)
	-- The right edge retreats; the art keeps its full width and fixed left edge after resizing.
	self.Fill.Size = UDim2.fromScale(if ratio > 0 then 1 / ratio else 1, 1)
	self.Clip.Visible = ratio > 0

	local low = ratio < STYLE.LowPatience
	if low ~= self.Low and self.Gradient and self.Calm then
		self.Gradient.Color = if low then STYLE.LowGradient else self.Calm
	end
	self.Low = low
	-- A guest about to give up shakes their bubble, so the urgent table stands out in a full room.
	if low and now >= self.NextWobbleAt then
		self.NextWobbleAt = now + STYLE.WobbleSeconds
		Animate.Swing(self.Panel, STYLE.WobbleDegrees)
	end
end

function Bubble.Show(self: Bubble, view: View): ()
	local choosing = view.State == "Choosing"
	local ordered = view.State == "Waiting"

	-- Placing the order is the moment the bubble changes meaning: punch it.
	if self.State ~= view.State then
		if self.State ~= "" and ordered then
			Animate.Pop(self.Panel, Config.Pop.Placed)
		end
		self.State = view.State
	end

	local names: { string } = {}
	local key = view.State
	if ordered then
		key = `{key}:{table.concat(view.Orders, ",")}`
	end
	if key ~= self.Key then
		self.Key = key
		for index, icon in self.Icons do
			local recipe = if ordered then Recipes:Get(view.Orders[index] or "") else nil
			icon.Visible = recipe ~= nil
			if recipe then
				FoodPreview.Show(icon, recipe)
			else
				FoodPreview.Clear(icon)
			end
		end
	end
	if ordered then
		for _, recipeId in view.Orders do
			local recipe = Recipes:Get(recipeId)
			if recipe then
				names[#names + 1] = recipe.name
			end
		end
	end

	self.Ponder.Visible = not ordered
	self.Ponder.Text = if choosing
		then string.rep(".", math.floor(view.Now / Config.PonderInterval) % 3 + 1)
		else "!"
	self.Caption.Text = if ordered
		then table.concat(names, " + ")
		elseif choosing then "Choosing..."
		else STYLE.QueuedText
	self.Badge.Visible = view.Seat ~= nil
	self.BadgeText.Text = view.Seat or ""
	self:SetRemaining(view.Remaining, view.Now)
end

function Bubble.Destroy(self: Bubble): ()
	self.Janitor:Destroy()
end

return Bubble
