--!strict
-- The level-up banner: rotating rays behind the gold star with the new level, the lettered title and
-- the recipes the level unlocked, with confetti. Non-interactive; it leaves on its own.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Feedback)
local Ease = require(ReplicatedStorage.Shared.UI.Ease)
local Sparks = require(ReplicatedStorage.Shared.UI.Sparks)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Types ]]--
type View = {
	Root: Frame,
	Scale: UIScale,
	Rays: ImageLabel,
	RaysScale: UIScale,
	InnerRays: ImageLabel,
	InnerRaysScale: UIScale,
	StarScale: UIScale,
	Number: TextLabel,
	NumberScale: UIScale,
	Title: Frame,
	TitleScale: UIScale,
	Subtitle: TextLabel,
	SubtitleStroke: UIStroke,
}

--[[ Constants ]]--
local TUNING = Config.LevelUp
local RAYS_POP_SECONDS = 0.5
local STAR_POP_SECONDS = 0.55
local STAR_POP_STRENGTH = 2.4
local NUMBER_DELAY = 0.12
local TITLE_DELAY = 0.16
local TITLE_DROP = 60
local TITLE_STROKE_THICKNESS = 5
local SUBTITLE_FROM, SUBTITLE_SECONDS = 0.45, 0.3
local CONFETTI_AT = 0.06
local CONFETTI_FAN = 160
local TWINKLES = 12
-- After the pop the star breathes gently.
local BREATH_AMPLITUDE, BREATH_SPEED = 0.035, 5
local INNER_RAYS_SIZE, INNER_RAYS_SPEED = 0.72, -1.6

--[[ Tables ]]--
local LevelUp = {}
LevelUp.__index = LevelUp

export type LevelUp = typeof(setmetatable(
	{} :: {
		Parent: GuiObject,
		Sparks: Sparks.Sparks,
		View: View?,
		StartedAt: number,
		Scale: number,
		Burst: boolean,
	},
	LevelUp
))

--[[ Private Functions ]]--
local function uiScale(parent: Instance, value: number): UIScale
	local object = Instance.new("UIScale")
	object.Scale = value
	object.Parent = parent
	return object
end

local function image(parent: Instance, name: string, asset: string, size: Vector2, zIndex: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.BackgroundTransparency = 1
	label.Image = asset
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

local function caption(parent: Instance, size: number, stroke: Color3, thickness: number): (TextLabel, UIStroke)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Title
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 6
	local outline = Instance.new("UIStroke")
	outline.Color = stroke
	outline.Thickness = thickness
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = label
	label.Parent = parent
	return label, outline
end

local function build(parent: GuiObject): View
	local root = Instance.new("Frame")
	root.Name = "LevelUp"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(TUNING.Anchor.X, TUNING.Anchor.Y)
	root.Size = UDim2.fromOffset(TUNING.RaysSize, TUNING.RaysSize)
	root.BackgroundTransparency = 1
	root.ZIndex = 10
	root.Parent = parent

	local rays = image(root, "Rays", TUNING.Rays, Vector2.one * TUNING.RaysSize, 1)
	rays.ImageColor3 = TUNING.RaysColor
	rays.ImageTransparency = 0.15
	local inner = image(root, "InnerRays", TUNING.Rays, Vector2.one * TUNING.RaysSize * INNER_RAYS_SIZE, 2)
	inner.ImageTransparency = 0.45

	local star = image(root, "Star", TUNING.Star, Vector2.one * TUNING.StarSize, 3)
	star.ScaleType = Enum.ScaleType.Fit
	local number = caption(star, TUNING.NumberTextSize, TUNING.NumberStroke, 5)
	-- The star's optical centre sits below its bounding-box centre.
	number.Position = UDim2.fromScale(0.5, 0.56)
	number.ZIndex = 4

	-- Bare lettering: a warm gradient under a heavy outline reads over any scene.
	local titleFrame = Instance.new("Frame")
	titleFrame.Name = "Title"
	titleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	titleFrame.Size = UDim2.fromOffset(TUNING.TitleBox.X, TUNING.TitleBox.Y)
	titleFrame.BackgroundTransparency = 1
	titleFrame.ZIndex = 5
	titleFrame.Parent = root
	local title = caption(titleFrame, TUNING.TitleTextSize, TUNING.TitleStroke, TITLE_STROKE_THICKNESS)
	title.Text = TUNING.Title
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(TUNING.TitleTop, TUNING.TitleBottom)
	gradient.Parent = title

	local subtitleFrame = Instance.new("Frame")
	subtitleFrame.Name = "Unlocks"
	subtitleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitleFrame.Position = UDim2.new(0.5, 0, 0.5, TUNING.StarSize / 2 + TUNING.SubtitleTextSize)
	subtitleFrame.Size = UDim2.fromOffset(TUNING.RaysSize, TUNING.SubtitleTextSize + 8)
	subtitleFrame.BackgroundTransparency = 1
	subtitleFrame.ZIndex = 5
	subtitleFrame.Parent = root
	local subtitle, subtitleStroke = caption(subtitleFrame, TUNING.SubtitleTextSize, TUNING.NumberStroke, 3)

	return {
		Root = root,
		Scale = uiScale(root, 1),
		Rays = rays,
		RaysScale = uiScale(rays, 0),
		InnerRays = inner,
		InnerRaysScale = uiScale(inner, 0),
		StarScale = uiScale(star, 0),
		Number = number,
		NumberScale = uiScale(number, 0),
		Title = titleFrame,
		TitleScale = uiScale(titleFrame, 0),
		Subtitle = subtitle,
		SubtitleStroke = subtitleStroke,
	}
end

--[[ Handling ]]--
function LevelUp.new(parent: GuiObject, sparks: Sparks.Sparks): LevelUp
	return setmetatable({
		Parent = parent,
		Sparks = sparks,
		View = nil,
		StartedAt = 0,
		Scale = 1,
		Burst = false,
	}, LevelUp)
end

function LevelUp.IsShowing(self: LevelUp): boolean
	return self.View ~= nil
end

--- Shows `level`; a second level up while the banner is still on screen restarts it with the new number.
function LevelUp.Show(self: LevelUp, level: number, unlocks: string, scale: number): ()
	local view = self.View or build(self.Parent)
	self.View = view
	self.StartedAt = os.clock()
	self.Scale = scale
	self.Burst = false
	view.Number.Text = tostring(level)
	view.Subtitle.Text = unlocks
	view.Subtitle.Visible = unlocks ~= ""
end

function LevelUp.Step(self: LevelUp, now: number): ()
	local view = self.View
	if not view then
		return
	end
	local age = now - self.StartedAt
	if age >= TUNING.Seconds + TUNING.ExitSeconds then
		view.Root:Destroy()
		self.View = nil
		return
	end

	if not self.Burst and age >= CONFETTI_AT then
		self.Burst = true
		local center = view.Root.AbsolutePosition + view.Root.AbsoluteSize / 2
		self.Sparks:Confetti(center, TUNING.Confetti, CONFETTI_FAN)
		self.Sparks:Twinkle(center, TWINKLES)
	end

	local exit = Ease.InBack((age - TUNING.Seconds) / TUNING.ExitSeconds)
	view.Scale.Scale = self.Scale * (1 - exit)

	view.RaysScale.Scale = Ease.OutBack(age / RAYS_POP_SECONDS)
	view.Rays.Rotation = TUNING.RaysSpeed * age
	view.InnerRaysScale.Scale = Ease.OutBack((age - 0.05) / RAYS_POP_SECONDS)
	view.InnerRays.Rotation = TUNING.RaysSpeed * INNER_RAYS_SPEED * age

	local breath = if age > STAR_POP_SECONDS then 1 + BREATH_AMPLITUDE * math.sin((age - STAR_POP_SECONDS) * BREATH_SPEED) else 1
	view.StarScale.Scale = Ease.OutBack(age / STAR_POP_SECONDS, STAR_POP_STRENGTH) * breath
	view.NumberScale.Scale = Ease.OutBack((age - NUMBER_DELAY) / STAR_POP_SECONDS, STAR_POP_STRENGTH)

	-- The title drops onto the star's top point.
	local drop = Ease.OutBack((age - TITLE_DELAY) / STAR_POP_SECONDS, 1.4)
	view.TitleScale.Scale = drop
	view.Title.Position = UDim2.new(
		0.5,
		0,
		0.5,
		-(TUNING.StarSize / 2 + TUNING.TitleBox.Y * 0.45) - TITLE_DROP * (1 - drop)
	)

	local shown = Ease.Clamp((age - SUBTITLE_FROM) / SUBTITLE_SECONDS)
	view.Subtitle.TextTransparency = 1 - shown
	view.SubtitleStroke.Transparency = 1 - shown
end

function LevelUp.Destroy(self: LevelUp): ()
	if self.View then
		self.View.Root:Destroy()
		self.View = nil
	end
end

return LevelUp
