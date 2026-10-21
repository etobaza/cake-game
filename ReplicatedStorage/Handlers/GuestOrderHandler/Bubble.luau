--!strict
-- One guest's speech bubble: the ordered dishes, their names, the seat number and the patience left.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Config = require(_Shared.Configs.Orders)
local FoodPreview = require(_Shared.UI.FoodPreview)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local SoundPlayer = require(_Shared.SoundPlayer)
local Theme = require(_Shared.UI.Theme)

--[[ Constants ]]--
local STYLE = Config.Bubble
local VOICE = STYLE.Voice

--[[ Types ]]--
export type View = {
	State: string,
	-- Done choosing and waiting for the player's Take order.
	Ready: boolean,
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
		Head: BasePart,
		-- Where the bubble sits above the head, fixed when it is created.
		Offset: Vector3,
		Janitor: any,
		Billboard: BillboardGui,
		-- Holds the layout at its configured pixels; Zoom scales it to the guest's world size.
		Root: Frame,
		Zoom: UIScale,
		Panel: Frame,
		Corner: UICorner,
		Strokes: { UIStroke },
		Tail: Frame,
		Seam: Frame,
		Row: Frame,
		RowLayout: UIListLayout,
		Icons: { ImageLabel },
		Ponder: TextLabel,
		Caption: TextLabel,
		Badge: Frame,
		BadgeText: TextLabel,
		Bar: CanvasGroup,
		Clip: Frame,
		Fill: Frame,
		Gradient: UIGradient?,
		-- The order HUD's own fill colours, restored once patience recovers (a placed order).
		Calm: ColorSequence?,
		Key: string,
		State: string,
		Low: boolean,
		NextWobbleAt: number,
		NextPulseAt: number,
		PonderColor: Color3,
		-- The caption being typed, the guest's voice and when it last spoke.
		Said: string,
		Voice: Sound,
		VoiceAt: number,
		-- Layout pixels, world scale (TextScale.World) and the dish lines the caption is sized for.
		Size: Vector2,
		Scale: number,
		Lines: number,
	},
	Bubble
))

--[[ Private Functions ]]--
local function round(parent: GuiObject, radius: UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

local function outline(parent: GuiObject): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelEdge
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- Fixed sizes without wrapping: the renderer fits and wraps text at its scaled pixel size, so
-- either would flip a line as the bubble scales with distance.
local function label(name: string, parent: GuiObject, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = Theme.Fonts.Bold
	text.TextColor3 = Theme.Colors.Cocoa
	text.TextSize = size
	text.Parent = parent
	return text
end

--[[ Handling ]]--
-- The bubble is depth-tested (see AlwaysOnTop below), so it sits above the guest's tallest
-- accessory instead of inside a tall hat.
function Bubble.HeadOffset(model: Model, head: BasePart): Vector3
	local top = -math.huge
	for _, accessory in model:GetChildren() do
		local handle = if accessory:IsA("Accessory") then accessory:FindFirstChild("Handle") else nil
		if not handle or not handle:IsA("BasePart") or handle.Transparency >= 1 then
			continue
		end
		local frame, half = handle.CFrame, handle.Size / 2
		local reach = math.abs(frame.RightVector.Y) * half.X
			+ math.abs(frame.UpVector.Y) * half.Y
			+ math.abs(frame.LookVector.Y) * half.Z
		top = math.max(top, frame.Position.Y + reach)
	end

	return Vector3.new(0, math.clamp(top - head.Position.Y + STYLE.HatMargin, STYLE.MinHeight, STYLE.MaxHeight), 0)
end

function Bubble.new(model: Model, head: BasePart, offset: Vector3, barTemplate: CanvasGroup, scale: number): Bubble
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OrderBubble"
	billboard.Adornee = head
	-- Grow upward from the anchor, so a taller bubble never sinks into the guest's head.
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.StudsOffsetWorldSpace = offset
	billboard.MaxDistance = STYLE.MaxDistance
	-- AlwaysOnTop billboards do not draw ViewportFrames or CanvasGroups: the dish preview and the
	-- patience bar would both vanish.
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	-- A CanvasGroup only draws under Sibling ordering; under Global the patience bar stays empty.
	-- Sibling ZIndex values below are ordered within each parent.
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Parent = billboard
	local zoom = Instance.new("UIScale")
	zoom.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Theme.Colors.PanelFill
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = root
	local corner = round(panel, UDim.new())

	-- A rotated square half hidden behind the panel points the bubble at the guest.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 1)
	tail.Rotation = 45
	tail.BackgroundColor3 = Theme.Colors.PanelFill
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	tail.Parent = panel
	-- Covers the tail's stroke where it crosses into the panel.
	local seam = Instance.new("Frame")
	seam.Name = "Seam"
	seam.AnchorPoint = Vector2.new(0.5, 1)
	seam.BackgroundColor3 = Theme.Colors.PanelFill
	seam.BorderSizePixel = 0
	seam.ZIndex = 3
	seam.Parent = panel

	local row = Instance.new("Frame")
	row.Name = "Dishes"
	row.BackgroundTransparency = 1
	row.ZIndex = 4
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local icons: { ImageLabel } = {}
	for index = 1, STYLE.MaxIcons do
		local icon = Instance.new("ImageLabel")
		icon.Name = `Dish{index}`
		icon.LayoutOrder = index
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Visible = false
		icon.ZIndex = 4
		icon.Parent = row
		icons[index] = icon
	end

	local ponder = label("Ponder", panel, STYLE.PonderSize)
	ponder.FontFace = Theme.Fonts.ExtraBold
	ponder.ZIndex = 4

	local caption = label("Caption", panel, STYLE.TextSize)
	caption.ZIndex = 4

	-- Preserve the order HUD's exact border, mask and striped artwork.
	local bar = barTemplate:Clone()
	bar.Name = "Patience"
	bar.AnchorPoint = Vector2.new(0, 1)
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
		Head = head,
		Offset = offset,
		Janitor = Janitor.new(),
		Billboard = billboard,
		Root = root,
		Zoom = zoom,
		Panel = panel,
		Corner = corner,
		Strokes = { outline(panel), outline(tail) },
		Tail = tail,
		Seam = seam,
		Row = row,
		RowLayout = layout,
		Icons = icons,
		Ponder = ponder,
		Caption = caption,
		Badge = badge,
		BadgeText = badgeText,
		Bar = bar,
		Clip = clip,
		Fill = fill,
		Gradient = gradient,
		Calm = if gradient then gradient.Color else nil,
		Key = "",
		State = "",
		Low = false,
		NextWobbleAt = 0,
		NextPulseAt = 0,
		PonderColor = ponder.TextColor3,
		Said = "",
		-- The guest's voice: one positional blip at the head, restarted per letter.
		Voice = SoundPlayer.Create("NpcText", head),
		VoiceAt = -math.huge,
		Size = Vector2.zero,
		Scale = scale,
		Lines = 0,
	}, Bubble)
	self:Layout()
	self.Janitor:Add(self.Voice, "Destroy")
	self.Janitor:Add(function(): ()
		for _, icon in icons do
			FoodPreview.Clear(icon)
		end
	end, true)
	self.Janitor:Add(billboard, "Destroy")
	-- A ViewportFrame draws nothing inside a BillboardGui that lives in the Workspace; under
	-- PlayerGui, with the head as Adornee, the dish preview renders. The handler destroys the bubble
	-- once its guest model is gone.
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Animate.Pop(panel, Config.Pop.Appear)
	return self
end

-- Sizes every piece at its configured pixels; the caption grows with its dish lines.
function Bubble.Layout(self: Bubble): ()
	local padding = STYLE.Padding
	local iconSize = STYLE.IconSize
	local captionHeight = math.max(STYLE.CaptionHeight, self.Lines * STYLE.LineHeight)
	local barHeight = STYLE.BarHeight
	local panelHeight = padding * 4 + iconSize + captionHeight + barHeight
	local width = STYLE.Width
	local stroke = STYLE.StrokeThickness
	local tail = STYLE.TailSize
	local badge = STYLE.BadgeSize

	self.Size = Vector2.new(width, panelHeight + tail)
	self.Root.Size = UDim2.fromOffset(self.Size.X, self.Size.Y)
	self:SetScale(self.Scale)
	self.Panel.Position = UDim2.new(0.5, 0, 0, panelHeight / 2)
	self.Panel.Size = UDim2.fromOffset(width - stroke * 2, panelHeight)
	self.Corner.CornerRadius = UDim.new(0, STYLE.CornerRadius)
	for _, edge in self.Strokes do
		edge.Thickness = stroke
	end
	self.Tail.Size = UDim2.fromOffset(tail * 1.4, tail * 1.4)
	self.Seam.Position = UDim2.new(0.5, 0, 1, stroke + 0.5)
	self.Seam.Size = UDim2.fromOffset(tail * 1.2, tail)

	self.Row.Position = UDim2.fromOffset(0, padding)
	self.Row.Size = UDim2.new(1, 0, 0, iconSize)
	self.RowLayout.Padding = UDim.new(0, STYLE.IconGap)
	for _, icon in self.Icons do
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
	end
	self.Ponder.Position = self.Row.Position
	self.Ponder.Size = self.Row.Size
	self.Caption.Position = UDim2.fromOffset(padding, padding * 2 + iconSize)
	self.Caption.Size = UDim2.new(1, -padding * 2, 0, captionHeight)
	self.Bar.Position = UDim2.new(0, padding, 1, -padding)
	self.Bar.Size = UDim2.new(1, -padding * 2, 0, barHeight)
	self.Badge.Position = UDim2.fromOffset(badge / 3, badge / 3)
	self.Badge.Size = UDim2.fromOffset(badge * 1.4, badge)
end

-- The handler keeps `scale` at the guest's world scale every frame, so the bubble shrinks smoothly
-- with distance like the guest.
function Bubble.SetScale(self: Bubble, scale: number): ()
	self.Scale = scale
	self.Zoom.Scale = scale
	self.Billboard.Size = UDim2.fromOffset(self.Size.X * scale, self.Size.Y * scale)
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

	-- Multiple dishes keep their full names on separate lines instead of shrinking one long sentence.
	if #names ~= self.Lines then
		self.Lines = #names
		self:Layout()
	end

	local ready = choosing and view.Ready
	self.Ponder.Visible = not ordered
	self.Ponder.Text = if choosing and not ready
		then string.rep(".", math.floor(view.Now / Config.PonderInterval) % 3 + 1)
		else "!"
	self.Ponder.TextColor3 = if ready then STYLE.ReadyMarkColor else self.PonderColor
	-- Ready to order: the bubble keeps beating until the player comes over.
	if ready and view.Now >= self.NextPulseAt then
		self.NextPulseAt = view.Now + Config.ReadyPulseSeconds
		Animate.Pop(self.Panel, STYLE.ReadyPulseFrom)
	end
	self:Say(
		if ordered
			then table.concat(names, "\n")
			elseif ready then STYLE.ReadyText
			elseif choosing then "Choosing..."
			else STYLE.QueuedText
	)
	self.Badge.Visible = view.Seat ~= nil
	self.BadgeText.Text = view.Seat or ""
	self:SetRemaining(view.Remaining, view.Now)
end

-- New words type out letter by letter with the guest's blip, like an NPC talking over its head.
function Bubble.Say(self: Bubble, text: string): ()
	if text == self.Said then
		return
	end
	self.Said = text
	self.Caption.Text = text
	self.Caption.MaxVisibleGraphemes = 0
	local letters = utf8.len(text) or #text
	local chars = {}
	for _, code in utf8.codes(text) do
		table.insert(chars, utf8.char(code))
	end
	local started = os.clock()
	local typed = 0
	self.Janitor:Add(
		RunService.RenderStepped:Connect(function(): ()
			local due = math.min(letters, math.floor((os.clock() - started) / VOICE.CharSeconds) + 1)
			while typed < due do
				typed += 1
				self:Blip(chars[typed])
			end
			self.Caption.MaxVisibleGraphemes = typed
			if typed >= letters then
				self.Caption.MaxVisibleGraphemes = -1
				self.Janitor:Remove("Typing")
			end
		end),
		"Disconnect",
		"Typing"
	)
end

function Bubble.Blip(self: Bubble, char: string?): ()
	if not char or not string.find(char, "^%w$") then
		return
	end
	-- Restarting the blip before this much of it has played turns the voice into a buzz.
	local now = os.clock()
	if now - self.VoiceAt < VOICE.Restart then
		return
	end
	self.VoiceAt = now
	self.Voice.PlaybackSpeed = 1 + (math.random() * 2 - 1) * VOICE.Spread
	self.Voice.TimePosition = 0
	self.Voice:Play()
end

function Bubble.Destroy(self: Bubble): ()
	self.Janitor:Destroy()
end

return Bubble
