--!strict
-- A compact bakery receipt over the world, with a separately sized, always tappable Skip control.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Configs.UpgradeReveal)
local Ease = require(Shared.UI.Ease)
local Sparks = require(Shared.UI.Sparks)
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
		Title: TextLabel,
		Benefit: TextLabel,
		Tag: TextLabel,
		Icon: ImageLabel,
		Skip: TextButton,
		Progress: Frame,
		Veil: Frame,
		Sparks: Sparks.Sparks,
		Connection: RBXScriptConnection,
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
	local veil = Instance.new("Frame")
	veil.Name = "Transition"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Config.Card.Veil
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.Parent = root
	local plate = Instance.new("CanvasGroup")
	plate.Name = "Receipt"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.BackgroundColor3 = Config.Card.Cream
	plate.BorderSizePixel = 0
	plate.GroupTransparency = 1
	plate.ZIndex = 2
	round(plate, 20)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Card.Edge
	stroke.Thickness = 3
	stroke.Parent = plate
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 250, 235), Config.Card.Cream)
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
	local tag = label(plate, "Tag", 13, true)
	tag.TextColor3 = Config.Card.Edge
	local title = label(plate, "Name", Config.Card.TitleSize, true)
	title.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 16
	constraint.MaxTextSize = Config.Card.TitleSize
	constraint.Parent = title
	local benefit = label(plate, "Benefit", Config.Card.BenefitSize, false)
	benefit.TextWrapped = true
	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = Config.Card.Accent
	track.BackgroundTransparency = 0.75
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -10)
	track.Size = UDim2.new(1, -32, 0, 3)
	track.Parent = plate
	round(track, 3)
	local progress = Instance.new("Frame")
	progress.Name = "Remaining"
	progress.Size = UDim2.fromScale(1, 1)
	progress.BorderSizePixel = 0
	progress.BackgroundColor3 = Config.Card.Accent
	progress.Parent = track
	round(progress, 3)
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.BackgroundColor3 = Config.Card.Cream
	skipButton.BackgroundTransparency = 0.05
	skipButton.TextColor3 = Theme.Colors.Cocoa
	skipButton.FontFace = Theme.Fonts.ExtraBold
	skipButton.TextSize = 18
	skipButton.AutoButtonColor = true
	skipButton.Size = UDim2.fromOffset(Config.Card.SkipWidth, Config.Card.SkipHeight)
	skipButton.ZIndex = 4
	round(skipButton, 14)
	skipButton.Parent = plate
	local connection = skipButton.Activated:Connect(skip)
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return setmetatable({
		Screen = screen,
		Root = root,
		Plate = plate,
		Scale = scale,
		Title = title,
		Benefit = benefit,
		Tag = tag,
		Icon = icon,
		Skip = skipButton,
		Progress = progress,
		Veil = veil,
		Sparks = Sparks.new(root),
		Connection = connection,
	}, Card)
end

function Card.Show(self: Card, id: string, level: number): ()
	local entry = Upgrades:Get(id)
	local spec = Config.Targets[id]
	self.Title.Text = Upgrades:GetDisplayName(id, level - 1)
	self.Benefit.Text = if id == "kitchen_oven" and level == 2
		then "Your third oven. Bake three batches at once."
		else if spec then spec.Benefit else if entry then entry.blurb else "Your bakery just got better."
	local category = if entry and entry.category == "Garden"
		then "GREENHOUSE"
		else if entry then string.upper(entry.category) else "BAKERY"
	self.Tag.Text = `NEW · {category}` .. (if entry and entry.maxLevel > 1 then ` · {level}/{entry.maxLevel}` else "")
	self.Icon.Image = if entry then entry.icon or "" else ""
	self.Screen.Enabled = true
	self.Plate.GroupTransparency = 1
	self:Layout()
	self.Sparks:Twinkle(self.Plate.AbsolutePosition + Vector2.new(45, 20), 5)
end

function Card.Layout(self: Card): ()
	local viewport = self.Root.AbsoluteSize
	local tuning = Config.Card
	local density = math.clamp(viewport.Y / 900, 0.85, 1.2)
	local width = math.min(tuning.Width * density, viewport.X - tuning.Margin * 2)
	local narrow = width < 400
	local iconSize = if narrow then 64 else tuning.IconSize * density
	local left = iconSize + 32
	local height = if narrow then tuning.NarrowHeight else math.max(tuning.MinHeight, tuning.Height * density)
	self.Plate.Size = UDim2.fromOffset(width, height)
	self.Plate.Position = UDim2.new(0.5, 0, 1, -math.max(18, tuning.Bottom * density))
	self.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
	self.Icon.Position = UDim2.fromOffset(14, (height - iconSize) / 2 - 3)
	self.Tag.Position = UDim2.fromOffset(14, 16)
	self.Tag.Size = UDim2.new(1, -tuning.SkipWidth - 40, 0, 18)
	self.Title.Position = UDim2.fromOffset(left, 55)
	self.Title.Size = UDim2.new(1, -left - 16, 0, 32)
	self.Benefit.Position = UDim2.fromOffset(left, 91)
	self.Benefit.Size = UDim2.new(1, -left - 16, 1, -113)
	self.Benefit.TextSize = math.max(16, tuning.BenefitSize * density)
	self.Skip.Position = UDim2.new(1, -12, 0, 8)
	local input = UserInputService.PreferredInput
	self.Skip.Text = if input == Enum.PreferredInput.Gamepad
		then "Skip  ·  B"
		elseif input == Enum.PreferredInput.Touch then "Skip"
		else "Skip  ·  Space"
end

function Card.Step(self: Card, deltaTime: number, age: number, duration: number, returning: boolean, veil: number): ()
	self:Layout()
	local arrive = Ease.OutCubic(age / Config.Card.EnterSeconds)
	self.Scale.Scale = 0.94 + 0.06 * Ease.OutBack(age / Config.Card.EnterSeconds, 0.4)
	self.Plate.GroupTransparency = if returning then math.min(age / Config.Card.ExitSeconds, 1) else 1 - arrive
	self.Progress.Size = UDim2.fromScale(math.clamp(1 - age / math.max(duration, 0.01), 0, 1), 1)
	self.Veil.BackgroundTransparency = 1 - math.clamp(veil, 0, 1)
	self.Sparks:Step(deltaTime)
end

function Card.Hide(self: Card): ()
	self.Sparks:Clear()
	self.Screen.Enabled = false
	self.Veil.BackgroundTransparency = 1
end

function Card.Destroy(self: Card): ()
	self.Connection:Disconnect()
	self.Sparks:Destroy()
	self.Screen:Destroy()
end

return Card
