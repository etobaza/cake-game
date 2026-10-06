--!strict
-- The streak milestone banner: a big flame beside the lettered milestone title, the run and its tip
-- bonus, and a fountain of fire-coloured confetti. Non-interactive; it leaves on its own.

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
	HeadlineScale: UIScale,
	Title: TextLabel,
	FlameScale: UIScale,
	Subtitle: TextLabel,
	SubtitleStroke: UIStroke,
}

--[[ Constants ]]--
local STREAK = Config.Streak
local TUNING = STREAK.Banner
local POP_SECONDS = 0.4
local POP_STRENGTH = 2
local FLAME_DELAY = 0.08
local SUBTITLE_FROM, SUBTITLE_SECONDS = 0.25, 0.25
local CONFETTI_FAN = 150
local EMBERS = 10
local TITLE_STROKE_THICKNESS = 5
local FLAME_GAP = 4

--[[ Tables ]]--
local StreakBanner = {}
StreakBanner.__index = StreakBanner

export type StreakBanner = typeof(setmetatable(
	{} :: {
		Parent: GuiObject,
		Sparks: Sparks.Sparks,
		View: View?,
		StartedAt: number,
		Scale: number,
		Burst: boolean,
	},
	StreakBanner
))

--[[ Private Functions ]]--
local function uiScale(parent: Instance, value: number): UIScale
	local object = Instance.new("UIScale")
	object.Scale = value
	object.Parent = parent
	return object
end

local function caption(parent: Instance, size: number, stroke: Color3, thickness: number): (TextLabel, UIStroke)
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.FontFace = Theme.Fonts.Title
	text.TextSize = size
	text.TextColor3 = Color3.new(1, 1, 1)
	text.ZIndex = 16
	local outline = Instance.new("UIStroke")
	outline.Color = stroke
	outline.Thickness = thickness
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = text
	text.Parent = parent
	return text, outline
end

local function build(parent: GuiObject): View
	local root = Instance.new("Frame")
	root.Name = "StreakBanner"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(TUNING.Anchor.X, TUNING.Anchor.Y)
	root.Size = UDim2.fromOffset(TUNING.Width, TUNING.TitleHeight + TUNING.SubtitleTextSize + 12)
	root.BackgroundTransparency = 1
	root.ZIndex = 14
	root.Parent = parent

	-- The flame and the title sit side by side and stay centred together, whatever the title's length.
	local headline = Instance.new("Frame")
	headline.Name = "Headline"
	headline.AnchorPoint = Vector2.new(0.5, 0)
	headline.Position = UDim2.fromScale(0.5, 0)
	headline.Size = UDim2.new(1, 0, 0, TUNING.TitleHeight)
	headline.BackgroundTransparency = 1
	headline.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, FLAME_GAP)
	layout.Parent = headline

	local flame = Instance.new("ImageLabel")
	flame.Name = "Flame"
	flame.Size = UDim2.fromOffset(TUNING.FlameSize, TUNING.FlameSize)
	flame.Rotation = -10
	flame.BackgroundTransparency = 1
	flame.Image = STREAK.Flame
	flame.ScaleType = Enum.ScaleType.Fit
	flame.LayoutOrder = 1
	flame.ZIndex = 17
	flame.Parent = headline

	-- Bare lettering in fire colours under a heavy outline, like the level-up title.
	local title = caption(headline, TUNING.TitleTextSize, TUNING.TitleStroke, TITLE_STROKE_THICKNESS)
	title.AnchorPoint = Vector2.zero
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.fromOffset(0, TUNING.TitleHeight)
	title.LayoutOrder = 2
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Rotation = 90
	titleGradient.Color = ColorSequence.new(TUNING.TitleTop, TUNING.TitleBottom)
	titleGradient.Parent = title

	local subtitleFrame = Instance.new("Frame")
	subtitleFrame.Name = "Run"
	subtitleFrame.AnchorPoint = Vector2.new(0.5, 1)
	subtitleFrame.Position = UDim2.fromScale(0.5, 1)
	subtitleFrame.Size = UDim2.new(1, 0, 0, TUNING.SubtitleTextSize + 8)
	subtitleFrame.BackgroundTransparency = 1
	subtitleFrame.Parent = root
	local subtitle, subtitleStroke = caption(subtitleFrame, TUNING.SubtitleTextSize, TUNING.TitleStroke, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(TUNING.SubtitleTop, TUNING.SubtitleBottom)
	gradient.Parent = subtitle

	return {
		Root = root,
		Scale = uiScale(root, 0),
		HeadlineScale = uiScale(headline, 0),
		Title = title,
		FlameScale = uiScale(flame, 0),
		Subtitle = subtitle,
		SubtitleStroke = subtitleStroke,
	}
end

--[[ Handling ]]--
function StreakBanner.new(parent: GuiObject, sparks: Sparks.Sparks): StreakBanner
	return setmetatable({
		Parent = parent,
		Sparks = sparks,
		View = nil,
		StartedAt = 0,
		Scale = 1,
		Burst = false,
	}, StreakBanner)
end

--- Shows (or restarts with) `title` over the `run` line.
function StreakBanner.Show(self: StreakBanner, title: string, run: string, scale: number): ()
	local view = self.View or build(self.Parent)
	self.View = view
	self.StartedAt = os.clock()
	self.Scale = scale
	self.Burst = false
	view.Title.Text = title
	view.Subtitle.Text = run
end

function StreakBanner.Step(self: StreakBanner, now: number): ()
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
	if not self.Burst then
		self.Burst = true
		local center = view.Root.AbsolutePosition + view.Root.AbsoluteSize / 2
		self.Sparks:Confetti(center, TUNING.Confetti, CONFETTI_FAN, STREAK.Colors)
		self.Sparks:Embers(center, EMBERS, STREAK.Colors[2])
	end

	local exit = Ease.InBack((age - TUNING.Seconds) / TUNING.ExitSeconds)
	view.Scale.Scale = self.Scale * (1 - exit)
	view.HeadlineScale.Scale = Ease.OutBack(age / POP_SECONDS, POP_STRENGTH)
	-- The flame keeps flickering for as long as the banner is up.
	local flicker = 1 + 0.06 * math.sin(age * 13) + 0.03 * math.sin(age * 7.3)
	view.FlameScale.Scale = Ease.OutBack((age - FLAME_DELAY) / POP_SECONDS, POP_STRENGTH) * flicker
	local shown = Ease.Clamp((age - SUBTITLE_FROM) / SUBTITLE_SECONDS)
	view.Subtitle.TextTransparency = 1 - shown
	view.SubtitleStroke.Transparency = 1 - shown
end

function StreakBanner.IsShowing(self: StreakBanner): boolean
	return self.View ~= nil
end

function StreakBanner.Destroy(self: StreakBanner): ()
	if self.View then
		self.View.Root:Destroy()
		self.View = nil
	end
end

return StreakBanner
