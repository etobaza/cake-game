--!strict
-- The floating sale label over a guest: the grade, the amount beside the HUD coin, and the streak.
-- Each line pops in after the previous one, then the label drifts up and fades.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Feedback)
local Ease = require(ReplicatedStorage.Shared.UI.Ease)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Types ]]--
type Line = { Scaler: UIScale, Delay: number }

export type Content = {
	Style: Config.GradeStyle,
	Amount: string,
	Streak: string?,
	-- Shown when this sale beat the all-time streak record.
	Record: string?,
	-- Pixel scale for this screen and grade.
	Scale: number,
}

--[[ Constants ]]--
local TUNING = Config.Popup
-- Popped lines overshoot noticeably: this is the moment the player reads.
local POP_STRENGTH = 2.2
-- How much the whole label shrinks while it fades.
local EXIT_SHRINK = 0.15
local LINE_PADDING = 8

--[[ Tables ]]--
local Popup = {}
Popup.__index = Popup

export type Popup = typeof(setmetatable(
	{} :: {
		Gui: BillboardGui,
		Anchor: Attachment?,
		Body: UIScale,
		Lines: { Line },
		Texts: { TextLabel },
		Strokes: { UIStroke },
		Images: { ImageLabel },
		Offset: Vector3,
		Scale: number,
		StartedAt: number,
	},
	Popup
))

--[[ Private Functions ]]--
local function scaler(parent: Instance, value: number): UIScale
	local object = Instance.new("UIScale")
	object.Scale = value
	object.Parent = parent
	return object
end

--[[ Handling ]]--
--- `adornee` is the guest's head, or nil to float above `position` instead.
function Popup.new(parent: Instance, adornee: BasePart?, position: Vector3, content: Content): Popup
	local style = content.Style
	local gradeHeight = TUNING.GradeTextSize + LINE_PADDING
	local amountHeight = TUNING.AmountTextSize + LINE_PADDING
	local streakHeight = if content.Streak then TUNING.StreakTextSize + LINE_PADDING else 0
	local recordHeight = if content.Record then TUNING.StreakTextSize + LINE_PADDING else 0
	local height = gradeHeight + amountHeight + streakHeight + recordHeight

	local gui = Instance.new("BillboardGui")
	gui.Name = "SalePopup"
	gui.Size = UDim2.fromOffset(TUNING.Width * content.Scale, height * content.Scale)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = TUNING.MaxDistance
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local anchor: Attachment? = nil
	if adornee then
		gui.Adornee = adornee
	else
		-- Terrain sits at the origin, so a terrain attachment's position is its world position.
		local point = Instance.new("Attachment")
		point.Name = "SalePopupAnchor"
		point.Position = position + Vector3.new(0, TUNING.FallbackLift, 0)
		point.Parent = workspace.Terrain
		gui.Adornee = point
		anchor = point
	end
	local offset = if adornee then TUNING.Offset else Vector3.zero
	gui.StudsOffsetWorldSpace = offset

	-- Content is laid out at design size and scaled as one, so the pop never re-flows the text.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(TUNING.Width, height)
	body.BackgroundTransparency = 1
	body.Parent = gui

	local self: Popup = setmetatable({
		Gui = gui,
		Anchor = anchor,
		Body = scaler(body, content.Scale),
		Lines = {},
		Texts = {},
		Strokes = {},
		Images = {},
		Offset = offset,
		Scale = content.Scale,
		StartedAt = os.clock(),
	}, Popup)

	local function text(
		parentFrame: Instance,
		value: string,
		size: number,
		font: Font,
		top: Color3,
		bottom: Color3,
		stroke: Color3
	): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Text = value
		label.TextSize = size
		label.FontFace = font
		label.TextColor3 = Color3.new(1, 1, 1)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(top, bottom)
		gradient.Rotation = 90
		gradient.Parent = label
		local outline = Instance.new("UIStroke")
		outline.Color = stroke
		outline.Thickness = TUNING.StrokeThickness
		outline.LineJoinMode = Enum.LineJoinMode.Round
		outline.Parent = label
		label.Parent = parentFrame
		table.insert(self.Texts, label)
		table.insert(self.Strokes, outline)
		return label
	end

	-- Centre-anchored so each line pops from its middle.
	local function line(name: string, top: number, lineHeight: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(TUNING.Width / 2, top + lineHeight / 2)
		frame.Size = UDim2.fromOffset(TUNING.Width, lineHeight)
		frame.BackgroundTransparency = 1
		frame.Parent = body
		table.insert(self.Lines, { Scaler = scaler(frame, 0), Delay = #self.Lines * TUNING.Stagger })
		return frame
	end

	local grade = text(
		line("Grade", 0, gradeHeight),
		style.Text,
		TUNING.GradeTextSize,
		Theme.Fonts.Title,
		style.Top,
		style.Bottom,
		style.Stroke
	)
	grade.Size = UDim2.fromScale(1, 1)
	grade.Rotation = TUNING.Tilt

	local amountRow = line("Amount", gradeHeight, amountHeight)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = amountRow
	local coin = Instance.new("ImageLabel")
	coin.Name = "Coin"
	coin.BackgroundTransparency = 1
	coin.Image = Config.Coins.Image
	coin.ScaleType = Enum.ScaleType.Fit
	coin.Size = UDim2.fromOffset(TUNING.CoinSize, TUNING.CoinSize)
	coin.LayoutOrder = 1
	coin.Parent = amountRow
	table.insert(self.Images, coin)
	local amount = text(
		amountRow,
		content.Amount,
		TUNING.AmountTextSize,
		Theme.Fonts.ExtraBold,
		TUNING.AmountTop,
		TUNING.AmountBottom,
		TUNING.AmountStroke
	)
	amount.AutomaticSize = Enum.AutomaticSize.X
	amount.Size = UDim2.fromOffset(0, amountHeight)
	amount.LayoutOrder = 2

	if content.Streak then
		local streak = text(
			line("Streak", gradeHeight + amountHeight, streakHeight),
			content.Streak,
			TUNING.StreakTextSize,
			Theme.Fonts.Title,
			Config.Streak.Top,
			Config.Streak.Bottom,
			Config.Streak.Stroke
		)
		streak.Size = UDim2.fromScale(1, 1)
	end

	if content.Record then
		local streakConfig = Config.Streak
		local record = text(
			line("Record", gradeHeight + amountHeight + streakHeight, recordHeight),
			content.Record,
			TUNING.StreakTextSize,
			Theme.Fonts.Title,
			streakConfig.RecordTop,
			streakConfig.RecordBottom,
			streakConfig.RecordStroke
		)
		record.Size = UDim2.fromScale(1, 1)
		record.Rotation = -TUNING.Tilt
	end

	gui.Parent = parent
	return self
end

--- Advances the animation; false once the popup has finished and should be destroyed.
function Popup.Step(self: Popup, now: number): boolean
	local age = now - self.StartedAt
	if age >= TUNING.Lifetime then
		return false
	end

	for _, entry in self.Lines do
		local progress = (age - entry.Delay) / TUNING.PopSeconds
		entry.Scaler.Scale = if progress <= 0 then 0 else Ease.OutBack(progress, POP_STRENGTH)
	end

	local rise = TUNING.Rise * Ease.OutCubic(age / TUNING.Lifetime)
	self.Gui.StudsOffsetWorldSpace = self.Offset + Vector3.new(0, rise, 0)

	local fade = Ease.Clamp((age - TUNING.FadeFrom) / (TUNING.Lifetime - TUNING.FadeFrom))
	self.Body.Scale = self.Scale * (1 - EXIT_SHRINK * fade)
	if fade > 0 then
		for _, label in self.Texts do
			label.TextTransparency = fade
		end
		for _, stroke in self.Strokes do
			stroke.Transparency = fade
		end
		for _, image in self.Images do
			image.ImageTransparency = fade
		end
	end
	return true
end

function Popup.Destroy(self: Popup): ()
	self.Gui:Destroy()
	if self.Anchor then
		self.Anchor:Destroy()
	end
end

return Popup
