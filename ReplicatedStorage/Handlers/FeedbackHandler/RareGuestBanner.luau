--!strict
-- Bounded arrival notices owned and stepped by FeedbackHandler; no replay from data snapshots.
-- A cream card with a tinted tag on its top edge, gold lettering between two swaying stars, and
-- chips for the tip multiplier and dish count that pop in after the card. A shine sweeps across once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Feedback = require(Shared.Configs.Feedback)
local Config = Feedback.RareGuest
local CustomerTypes = require(Shared.Configs.Registries.CustomerTypes)
local Ease = require(Shared.UI.Ease)
local SoundPlayer = require(Shared.SoundPlayer)
local TextScale = require(Shared.UI.TextScale)
local Theme = require(Shared.UI.Theme)

type Notice = { GuestId: string, TypeId: string, ExpiresAt: number }
type Chip = { Frame: Frame, Label: TextLabel, Stroke: UIStroke, Scale: UIScale }
-- Centre row and scale for a banner reaching `above` and `below` its centre at design size.
type Place = (anchor: number, above: number, below: number) -> (number, number)

-- The tag pill straddles the top edge and the shadow plate drops below the card.
local TAG_HEIGHT = 28
local SHADOW_DROP = 6
-- Pixels kept clear on each side of a narrow screen.
local SIDE_MARGIN = 12

local RareGuestBanner = {}
RareGuestBanner.__index = RareGuestBanner

export type RareGuestBanner = typeof(setmetatable(
	{} :: {
		Root: Frame,
		Scale: UIScale,
		Place: Place,
		Fit: number,
		Title: TextLabel,
		TitleLimit: UITextSizeConstraint,
		Tag: Frame,
		Stars: { ImageLabel },
		TipChip: Chip,
		DishChip: Chip,
		Shine: UIGradient,
		Queue: { Notice },
		Current: Notice?,
		Age: number,
		LastAt: number,
	},
	RareGuestBanner
))

local function corner(parent: GuiObject, radius: UDim): ()
	local object = Instance.new("UICorner")
	object.CornerRadius = radius
	object.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local object = Instance.new("UIStroke")
	object.Color = color
	object.Thickness = thickness
	object.LineJoinMode = Enum.LineJoinMode.Round
	object.Parent = parent
	return object
end

local function gradient(parent: GuiObject, top: Color3, bottom: Color3): ()
	local object = Instance.new("UIGradient")
	object.Rotation = 90
	object.Color = ColorSequence.new(top, bottom)
	object.Parent = parent
end

local function plate(parent: Instance, name: string, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

-- A pill sized to its text, with a cocoa caption.
local function pill(parent: Instance, name: string, height: number, textSize: number, zIndex: number): (Frame, TextLabel, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, height)
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	corner(frame, Theme.Corners.Pill)
	local outline = stroke(frame, Theme.Colors.PanelEdge, 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame
	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.ExtraBold
	label.TextColor3 = Theme.Colors.Cocoa
	label.TextSize = textSize
	label.ZIndex = zIndex
	label.Parent = frame
	frame.Parent = parent
	return frame, label, outline
end

local function chip(parent: Instance, name: string, order: number): Chip
	local frame, label, outline = pill(parent, name, Config.ChipTextSize + 12, Config.ChipTextSize, 6)
	frame.LayoutOrder = order
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = frame
	return { Frame = frame, Label = label, Stroke = outline, Scale = scale }
end

local function star(parent: Instance, x: UDim): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Star"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.new(x, UDim.new(0.5, 0))
	image.Size = UDim2.fromOffset(Config.StarSize, Config.StarSize)
	image.BackgroundTransparency = 1
	image.Image = Config.Star
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 6
	image.Parent = parent
	return image
end

-- Darkens a pastel guest colour enough to outline it.
local function shade(color: Color3): Color3
	return color:Lerp(Color3.new(0, 0, 0), 0.35)
end

function RareGuestBanner.new(parent: GuiObject, place: Place): RareGuestBanner
	local root = Instance.new("Frame")
	root.Name = "RareGuestBanner"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(Config.Anchor.X, Config.Anchor.Y)
	root.Size = UDim2.fromOffset(Config.Width, Config.Height)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local shadow = plate(root, "Shadow", 1)
	shadow.Position = UDim2.fromOffset(0, SHADOW_DROP)
	shadow.BackgroundColor3 = Config.ShadowColor
	shadow.BackgroundTransparency = 0.55
	corner(shadow, UDim.new(0, Config.Corner))

	local card = plate(root, "Card", 2)
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(card, UDim.new(0, Config.Corner))
	gradient(card, Config.FillTop, Config.FillBottom)
	stroke(card, Theme.Colors.PanelEdge, 4)

	-- A light inner rim gives the card a stitched, double-framed edge.
	local rim = plate(card, "Rim", 3)
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -12, 1, -12)
	rim.BackgroundTransparency = 1
	corner(rim, UDim.new(0, Config.Corner - 6))
	stroke(rim, Color3.new(1, 1, 1), 2).Transparency = 0.3

	-- A narrow white band that the step slides across the card once it lands.
	local gloss = plate(card, "Shine", 4)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(gloss, UDim.new(0, Config.Corner))
	local shine = Instance.new("UIGradient")
	shine.Rotation = 20
	shine.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shine.Offset = Vector2.new(-1, 0)
	shine.Parent = gloss

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(Config.StarInset * 2, 20)
	title.Size = UDim2.new(1, -Config.StarInset * 4, 0, 46)
	title.BackgroundTransparency = 1
	title.FontFace = Theme.Fonts.Title
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.ZIndex = 6
	gradient(title, Config.TitleTop, Config.TitleBottom)
	stroke(title, Config.TitleStroke, 3)
	-- Bound per notice: the constraint counts rendered pixels under the card's UIScale.
	local limit = Instance.new("UITextSizeConstraint")
	limit.Parent = title
	title.Parent = card

	local row = Instance.new("Frame")
	row.Name = "Chips"
	row.Position = UDim2.fromOffset(0, 70)
	row.Size = UDim2.new(1, 0, 0, Config.ChipTextSize + 12)
	row.BackgroundTransparency = 1
	row.ZIndex = 6
	row.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row

	local tipChip = chip(row, "Tips", 1)
	tipChip.Frame.BackgroundColor3 = Config.TipChip
	tipChip.Stroke.Color = Theme.Colors.Gold

	local tag, tagLabel = pill(root, "Tag", TAG_HEIGHT, 16, 7)
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Position = UDim2.fromScale(0.5, 0)
	tag.BackgroundColor3 = Theme.Colors.PanelEdge
	tagLabel.Text = Config.Tag
	tagLabel.FontFace = Theme.Fonts.Title

	return setmetatable({
		Root = root,
		Scale = scale,
		Place = place,
		Fit = 1,
		Title = title,
		TitleLimit = limit,
		Tag = tag,
		Stars = { star(card, UDim.new(0, Config.StarInset)), star(card, UDim.new(1, -Config.StarInset)) },
		TipChip = tipChip,
		DishChip = chip(row, "Dishes", 2),
		Shine = shine,
		Queue = {},
		Current = nil,
		Age = 0,
		LastAt = os.clock(),
	}, RareGuestBanner)
end

function RareGuestBanner.Push(self: RareGuestBanner, guestId: string, typeId: string): ()
	local entry = CustomerTypes:Get(typeId)
	if not entry or not entry.arrivalTitle or (self.Current and self.Current.GuestId == guestId) then
		return
	end
	for _, notice in self.Queue do
		if notice.GuestId == guestId then
			return
		end
	end
	if #self.Queue >= Config.MaxQueued then
		table.remove(self.Queue, 1)
	end
	table.insert(self.Queue, { GuestId = guestId, TypeId = typeId, ExpiresAt = os.clock() + Config.QueueSeconds })
end

function RareGuestBanner.Step(self: RareGuestBanner, now: number, blocked: boolean, exists: (string) -> boolean): ()
	local elapsed = now - self.LastAt
	self.LastAt = now
	for index = #self.Queue, 1, -1 do
		if self.Queue[index].ExpiresAt <= now then
			table.remove(self.Queue, index)
		end
	end
	if self.Current and not exists(self.Current.GuestId) then
		self.Current = nil
	end
	if blocked then
		self.Root.Visible = false
		return
	end
	if not self.Current then
		for index, notice in self.Queue do
			if not exists(notice.GuestId) then
				continue
			end
			table.remove(self.Queue, index)
			local entry = CustomerTypes:Get(notice.TypeId)
			if entry and entry.arrivalTitle then
				self.Current = notice
				self.Age = 0
				self.Title.Text = entry.arrivalTitle
				self.Tag.BackgroundColor3 = entry.color
				self.TipChip.Label.Text = if entry.coinMultiplier
					then string.format(Config.CoinFormat, tostring(entry.coinMultiplier))
					else string.format(Config.TipFormat, tostring(entry.tipMultiplier))
				self.DishChip.Label.Text = string.format(
					Config.DishFormat,
					entry.orders,
					if entry.orders == 1 then "DISH" else "DISHES"
				)
				self.DishChip.Frame.BackgroundColor3 = entry.color
				self.DishChip.Stroke.Color = shade(entry.color)
				self:Layout()
				SoundPlayer.Play(Config.Sound)
			end
			break
		end
	else
		self.Age += elapsed
		if self.Age >= Config.Seconds + Config.ExitSeconds then
			self.Current = nil
		end
	end
	self.Root.Visible = self.Current ~= nil
	if not self.Current then
		return
	end

	local age = self.Age
	self.Scale.Scale = self.Fit
		* Ease.OutBack(age / Config.PopSeconds)
		* (1 - Ease.Clamp((age - Config.Seconds) / Config.ExitSeconds))
	for index, item in { self.TipChip, self.DishChip } do
		local delay = Config.PopSeconds * 0.6 + (index - 1) * Config.ChipStagger
		item.Scale.Scale = Ease.OutBack((age - delay) / Config.ChipPopSeconds, 1.5)
	end
	local sway = math.sin(age * Config.StarSwaySpeed) * Config.StarSway
	self.Stars[1].Rotation = -sway
	self.Stars[2].Rotation = sway
	local sweep = Ease.OutCubic((age - Config.PopSeconds) / Config.ShineSeconds)
	self.Shine.Offset = Vector2.new(-1 + 2 * sweep, 0)
end

-- Sizes and rows the card for the notice it is about to show.
function RareGuestBanner.Layout(self: RareGuestBanner): ()
	local center, scale =
		self.Place(Config.Anchor.Y, Config.Height / 2 + TAG_HEIGHT / 2, Config.Height / 2 + SHADOW_DROP)
	local parent = self.Root.Parent :: GuiObject
	local fit = math.min(scale, (parent.AbsoluteSize.X - SIDE_MARGIN * 2) / Config.Width)
	self.Fit = fit
	self.Root.Position = UDim2.new(Config.Anchor.X, 0, 0, center)
	local floor = Theme.ScreenScale.MinTextPixels / fit
	TextScale.Bound(
		self.TitleLimit,
		math.max(Config.TitleMinTextSize, floor),
		math.max(Config.TitleTextSize, floor),
		fit
	)
end

function RareGuestBanner.Destroy(self: RareGuestBanner): ()
	table.clear(self.Queue)
	self.Current = nil
	self.Root:Destroy()
end

return RareGuestBanner
