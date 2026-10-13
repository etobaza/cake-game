--!strict
-- A compact bakery receipt over the world, with a separately sized, always tappable Skip control.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Configs.UpgradeReveal)
local Ease = require(Shared.UI.Ease)
local Metrics = require(script.Parent.Metrics)
local Sparks = require(Shared.UI.Sparks)
local TextScale = require(Shared.UI.TextScale)
local Theme = require(Shared.UI.Theme)
local Upgrades = require(Shared.Configs.Registries.Upgrades)

local Card = {}
Card.__index = Card
export type Card = typeof(setmetatable(
	{} :: {
		Screen: ScreenGui,
		Root: Frame,
		Plate: CanvasGroup,
		Scale: UIScale,
		-- Screen density from the last layout; the arrival pop multiplies it.
		Fit: number,
		Title: TextLabel,
		TitleLimit: UITextSizeConstraint,
		Benefit: TextLabel,
		Tag: TextLabel,
		Icon: ImageLabel,
		Skip: TextButton,
		Progress: Frame,
		Veil: Frame,
		Sparks: Sparks.Sparks,
		Connections: { RBXScriptConnection },
		-- Receipt top-left inside Root, from the last layout rather than a possibly stale AbsolutePosition.
		Corner: Vector2,
		TwinklePending: boolean,
	},
	Card
))

local function round(parent: GuiObject, radius: number): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function label(parent: Instance, name: string, size: number, bold: boolean): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = if bold then Theme.Fonts.ExtraBold else Theme.Fonts.SemiBold
	text.TextColor3 = Theme.Colors.Cocoa
	text.TextSize = size
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.Parent = parent
	return text
end

function Card.new(skip: () -> ()): Card
	local screen = Instance.new("ScreenGui")
	screen.Name = "UpgradeReveal"
	screen.ResetOnSpawn = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.DisplayOrder = Config.DisplayOrder
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screen
	local tuning = Config.Card
	local veil = Instance.new("Frame")
	veil.Name = "Transition"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = tuning.Veil
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.Parent = root
	local plate = Instance.new("CanvasGroup")
	plate.Name = "Receipt"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.BackgroundColor3 = tuning.Cream
	plate.BorderSizePixel = 0
	plate.GroupTransparency = 1
	plate.ZIndex = 2
	round(plate, tuning.Corner)
	local stroke = Instance.new("UIStroke")
	stroke.Color = tuning.Edge
	stroke.Thickness = tuning.EdgeThickness
	stroke.Parent = plate
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(tuning.Shine, tuning.Cream)
	gradient.Rotation = 90
	gradient.Parent = plate
	plate.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = plate
	local icon = Instance.new("ImageLabel")
	icon.Name = "UpgradeIcon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = plate
	local tag = label(plate, "Tag", tuning.TagSize, true)
	tag.TextColor3 = tuning.Edge
	local title = label(plate, "Name", tuning.TitleSize, true)
	title.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.Parent = title
	local benefit = label(plate, "Benefit", tuning.BenefitSize, false)
	benefit.TextWrapped = true
	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = tuning.Accent
	track.BackgroundTransparency = tuning.TrackTransparency
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -tuning.TrackInset)
	track.Size = UDim2.new(1, -tuning.TrackSidePadding * 2, 0, tuning.TrackHeight)
	track.Parent = plate
	round(track, tuning.TrackHeight)
	local progress = Instance.new("Frame")
	progress.Name = "Remaining"
	progress.Size = UDim2.fromScale(1, 1)
	progress.BorderSizePixel = 0
	progress.BackgroundColor3 = tuning.Accent
	progress.Parent = track
	round(progress, tuning.TrackHeight)
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.BackgroundColor3 = tuning.Cream
	skipButton.BackgroundTransparency = tuning.SkipTransparency
	skipButton.TextColor3 = Theme.Colors.Cocoa
	skipButton.FontFace = Theme.Fonts.ExtraBold
	skipButton.AutoButtonColor = true
	skipButton.ZIndex = 4
	round(skipButton, tuning.SkipCorner)
	skipButton.Parent = plate
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local self: Card = setmetatable({
		Screen = screen,
		Root = root,
		Plate = plate,
		Scale = scale,
		Fit = 1,
		Title = title,
		TitleLimit = constraint,
		Benefit = benefit,
		Tag = tag,
		Icon = icon,
		Skip = skipButton,
		Progress = progress,
		Veil = veil,
		Sparks = Sparks.new(root),
		Connections = {},
		Corner = Vector2.zero,
		TwinklePending = false,
	}, Card)
	-- Layout follows the viewport and the input device (Skip's hint and touch size); neither runs per frame.
	table.insert(self.Connections, skipButton.Activated:Connect(skip))
	table.insert(
		self.Connections,
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function(): ()
			self:Layout()
		end)
	)
	table.insert(
		self.Connections,
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function(): ()
			self:RefreshSkip()
			self:Layout()
		end)
	)
	self:RefreshSkip()
	return self
end

function Card.Show(self: Card, id: string, level: number): ()
	local entry = Upgrades:Get(id)
	local spec = Config.Targets[id]
	local tuning = Config.Card
	local levelBenefit = spec and spec.LevelBenefits and spec.LevelBenefits[level]
	self.Title.Text = Upgrades:GetDisplayName(id, level - 1)
	self.Benefit.Text = if levelBenefit
		then levelBenefit
		elseif spec then spec.Benefit
		elseif entry then entry.blurb
		else tuning.FallbackBenefit
	local category = if entry
		then tuning.CategoryLabels[entry.category] or string.upper(entry.category)
		else tuning.FallbackCategory
	self.Tag.Text = `NEW · {category}` .. (if entry and entry.maxLevel > 1 then ` · {level}/{entry.maxLevel}` else "")
	self.Icon.Image = if entry then entry.icon or "" else ""
	self.Screen.Enabled = true
	self.Plate.GroupTransparency = 1
	self:Layout()
	-- The plate's AbsolutePosition is stale until the engine lays it out; burst on the next Step.
	self.TwinklePending = true
end

--- Lays the receipt out in logical pixels; its UIScale draws them at the screen's density.
function Card.Layout(self: Card): ()
	local area = self.Root.AbsoluteSize
	local tuning = Config.Card
	local metrics = Metrics.Card(area)
	local scale = metrics.Scale
	local width, height, drop = metrics.Width, metrics.Height, metrics.Drop
	local floor = Theme.ScreenScale.MinTextPixels / scale
	local iconSize = if metrics.Narrow then tuning.NarrowIconSize else tuning.IconSize * metrics.Density
	local left = iconSize + tuning.TextColumnGap
	local textInset = -left - tuning.RightPadding
	self.Fit = scale
	self.Sparks:SetScale(scale)
	self.Plate.Size = UDim2.fromOffset(width, height)
	self.Plate.Position = UDim2.new(0.5, 0, 1, -metrics.Bottom * scale)
	self.Corner = Vector2.new((area.X - width * scale) / 2, area.Y - (metrics.Bottom + height) * scale)
	self.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
	self.Icon.Position = UDim2.fromOffset(tuning.Padding, drop + (height - drop - iconSize) / 2 - tuning.IconLift)
	self.Tag.Position = UDim2.fromOffset(tuning.Padding, tuning.TagTop)
	self.Tag.Size = UDim2.new(1, -metrics.Skip.X - tuning.TagSkipGap, 0, tuning.TagHeight)
	self.Tag.TextSize = math.max(tuning.TagSize, floor)
	self.Title.Position = UDim2.fromOffset(left, tuning.TitleTop + drop)
	self.Title.Size = UDim2.new(1, textInset, 0, tuning.TitleHeight)
	-- Text constraints count rendered pixels under the receipt's UIScale.
	TextScale.Bound(self.TitleLimit, math.max(tuning.MinTitleSize, floor), math.max(tuning.TitleSize, floor), scale)
	self.Benefit.Position = UDim2.fromOffset(left, tuning.BenefitTop + drop)
	self.Benefit.Size = UDim2.new(1, textInset, 1, -tuning.BenefitTop - drop - tuning.BenefitBottom)
	self.Benefit.TextSize = math.max(tuning.MinBenefitSize, tuning.BenefitSize * metrics.Density, floor)
	self.Skip.Position = UDim2.new(1, -tuning.SkipInset.X, 0, tuning.SkipInset.Y)
	self.Skip.Size = UDim2.fromOffset(metrics.Skip.X, metrics.Skip.Y)
	self.Skip.TextSize = math.max(tuning.SkipTextSize, floor)
end

function Card.RefreshSkip(self: Card): ()
	local input = UserInputService.PreferredInput
	self.Skip.Text = if input == Enum.PreferredInput.Gamepad
		then "Skip  ·  B"
		elseif input == Enum.PreferredInput.Touch then "Skip"
		else "Skip  ·  Space"
end

function Card.Step(self: Card, deltaTime: number, age: number, duration: number, returning: boolean, veil: number): ()
	local tuning = Config.Card
	if self.TwinklePending then
		self.TwinklePending = false
		self.Sparks:Twinkle(
			self.Root.AbsolutePosition + self.Corner + tuning.TwinkleOffset * self.Fit,
			tuning.TwinkleCount
		)
	end
	local arrive = Ease.OutCubic(age / tuning.EnterSeconds)
	self.Scale.Scale = self.Fit
		* (tuning.EnterScale + (1 - tuning.EnterScale) * Ease.OutBack(age / tuning.EnterSeconds, tuning.EnterOvershoot))
	self.Plate.GroupTransparency = if returning then math.min(age / tuning.ExitSeconds, 1) else 1 - arrive
	self.Progress.Size = UDim2.fromScale(math.clamp(1 - age / math.max(duration, 0.01), 0, 1), 1)
	self.Veil.BackgroundTransparency = 1 - math.clamp(veil, 0, 1)
	self.Sparks:Step(deltaTime)
end

function Card.Hide(self: Card): ()
	self.TwinklePending = false
	self.Sparks:Clear()
	self.Screen.Enabled = false
	self.Veil.BackgroundTransparency = 1
end

function Card.Destroy(self: Card): ()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self.Sparks:Destroy()
	self.Screen:Destroy()
end

return Card
