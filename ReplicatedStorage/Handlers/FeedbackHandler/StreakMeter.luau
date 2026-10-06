--!strict
-- The HUD streak flame beside the coin balance: the current run, the tip bonus the next good sale
-- earns, a punch on every step, and a puff of smoke when a mistake ends the run. It follows the HUD
-- coin every frame, so it slides away with the HUD while a page is open.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Feedback)
local Ease = require(ReplicatedStorage.Shared.UI.Ease)
local Economy = require(ReplicatedStorage.Shared.Configs.Economy)
local Sparks = require(ReplicatedStorage.Shared.UI.Sparks)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Types ]]--
type Tier = { From: number, Glow: Color3, Top: Color3, Bottom: Color3, Scale: number }

type View = {
	Root: Frame,
	Scale: UIScale,
	Glow: ImageLabel,
	Flame: ImageLabel,
	FlameScale: UIScale,
	Count: TextLabel,
	CountGradient: UIGradient,
	CountStroke: UIStroke,
	Bonus: TextLabel,
	BonusStroke: UIStroke,
	Puff: ImageLabel,
	PuffScale: UIScale,
	Lost: TextLabel,
	LostStroke: UIStroke,
}

--[[ Constants ]]--
local STREAK = Config.Streak
local TUNING = STREAK.Meter
local APPEAR_SECONDS = 0.35
local PUNCH_SECONDS = 0.35
local PUNCH_SIZE = 0.35
local VANISH_SECONDS = 0.25
local LOST_RISE = 34
-- Flicker: two detuned waves keep the flame from pulsing like a metronome.
local FLICKER_FAST, FLICKER_SLOW, FLICKER_SWAY = 13, 7.3, 5.1
local GLOW_SIZE = 2.3
local CONTENT_WIDTH = 190

--[[ Tables ]]--
local StreakMeter = {}
StreakMeter.__index = StreakMeter

export type StreakMeter = typeof(setmetatable(
	{} :: {
		View: View,
		Sparks: Sparks.Sparks,
		-- Absolute centre and size of the HUD coin, or nil while the HUD is covered.
		Anchor: () -> (Vector2?, Vector2?),
		Count: number,
		Tier: Tier,
		ShownAt: number,
		HiddenAt: number?,
		PunchedAt: number,
		LostAt: number?,
		EmberAt: number,
	},
	StreakMeter
))

--[[ Private Functions ]]--
local function uiScale(parent: Instance, value: number): UIScale
	local object = Instance.new("UIScale")
	object.Scale = value
	object.Parent = parent
	return object
end

local function outline(parent: Instance, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = TUNING.StrokeThickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

local function label(parent: Instance, size: number, position: UDim2, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = position
	text.Size = UDim2.fromOffset(CONTENT_WIDTH, height)
	text.FontFace = Theme.Fonts.Title
	text.TextSize = size
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.ZIndex = 12
	text.Parent = parent
	return text
end

local function tierFor(count: number): Tier
	local chosen: Tier = STREAK.Tiers[1]
	for _, tier in STREAK.Tiers do
		if count >= tier.From then
			chosen = tier
		end
	end
	return chosen
end

local function build(parent: GuiObject): View
	local flameSize = TUNING.FlameSize
	local root = Instance.new("Frame")
	root.Name = "StreakMeter"
	root.AnchorPoint = Vector2.new(0, 0.5)
	root.Size = UDim2.fromOffset(flameSize + CONTENT_WIDTH, flameSize)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 10
	root.Parent = parent

	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(flameSize / 2, flameSize / 2)
	glow.Size = UDim2.fromOffset(flameSize * GLOW_SIZE, flameSize * GLOW_SIZE)
	glow.BackgroundTransparency = 1
	glow.Image = STREAK.Glow
	glow.ZIndex = 10
	glow.Parent = root

	local flame = Instance.new("ImageLabel")
	flame.Name = "Flame"
	-- Anchored at its base so the flicker stretches the tips, not the bottom.
	flame.AnchorPoint = Vector2.new(0.5, 1)
	flame.Position = UDim2.fromOffset(flameSize / 2, flameSize)
	flame.Size = UDim2.fromOffset(flameSize, flameSize)
	flame.BackgroundTransparency = 1
	flame.Image = STREAK.Flame
	flame.ScaleType = Enum.ScaleType.Fit
	flame.ZIndex = 11
	flame.Parent = root

	local puff = Instance.new("ImageLabel")
	puff.Name = "Puff"
	puff.AnchorPoint = Vector2.new(0.5, 0.5)
	puff.Position = UDim2.fromOffset(flameSize / 2, flameSize / 2)
	puff.Size = UDim2.fromOffset(flameSize * 1.2, flameSize * 1.2)
	puff.BackgroundTransparency = 1
	puff.Image = STREAK.Puff
	puff.ScaleType = Enum.ScaleType.Fit
	puff.Visible = false
	puff.ZIndex = 13
	puff.Parent = root

	local count = label(root, TUNING.CountTextSize, UDim2.new(0, flameSize + 4, 0.38, 0), TUNING.CountTextSize)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = count
	local bonus = label(root, TUNING.BonusTextSize, UDim2.new(0, flameSize + 6, 0.86, 0), TUNING.BonusTextSize)
	local bonusGradient = Instance.new("UIGradient")
	bonusGradient.Rotation = 90
	bonusGradient.Color = ColorSequence.new(TUNING.BonusTop, TUNING.BonusBottom)
	bonusGradient.Parent = bonus

	local lost = label(root, TUNING.BonusTextSize + 4, UDim2.fromOffset(0, -12), TUNING.BonusTextSize + 4)
	lost.Text = STREAK.LostText
	lost.TextColor3 = Color3.fromRGB(220, 220, 220)
	lost.Visible = false

	return {
		Root = root,
		Scale = uiScale(root, 0),
		Glow = glow,
		Flame = flame,
		FlameScale = uiScale(flame, 1),
		Count = count,
		CountGradient = gradient,
		CountStroke = outline(count, TUNING.Stroke),
		Bonus = bonus,
		BonusStroke = outline(bonus, TUNING.Stroke),
		Puff = puff,
		PuffScale = uiScale(puff, 0),
		Lost = lost,
		LostStroke = outline(lost, Color3.fromRGB(40, 40, 40)),
	}
end

--[[ Handling ]]--
function StreakMeter.new(parent: GuiObject, anchor: () -> (Vector2?, Vector2?), sparks: Sparks.Sparks): StreakMeter
	return setmetatable({
		View = build(parent),
		Sparks = sparks,
		Anchor = anchor,
		Count = 0,
		Tier = tierFor(1),
		ShownAt = 0,
		HiddenAt = nil,
		PunchedAt = -math.huge,
		LostAt = nil,
		EmberAt = 0,
	}, StreakMeter)
end

--- The replicated streak changed. Growth punches the flame; a reset without `Lose` fades it out.
function StreakMeter.Set(self: StreakMeter, count: number, now: number): ()
	local previous = self.Count
	if count == previous then
		return
	end
	self.Count = count
	if count > 0 and previous == 0 then
		self.ShownAt = now
		self.HiddenAt = nil
		self.LostAt = nil
	elseif count > previous then
		self.PunchedAt = now
		local flame = self.View.Flame
		self.Sparks:Embers(flame.AbsolutePosition + flame.AbsoluteSize / 2, 4, tierFor(count).Glow)
	elseif count == 0 and not self.LostAt then
		self.HiddenAt = now
	end
	-- A reset keeps the last run on screen while it fades or snuffs out.
	if count == 0 then
		return
	end
	local view = self.View
	self.Tier = tierFor(count)
	view.Count.Text = `x{count}`
	view.Bonus.Text = string.format(TUNING.BonusFormat, math.round(Economy.GetStreakTipBonus(count) * 100))
	view.CountGradient.Color = ColorSequence.new(self.Tier.Top, self.Tier.Bottom)
	view.Glow.ImageColor3 = self.Tier.Glow
end

--- A mistake ended a run of `lost`: the flame snuffs out into a puff.
function StreakMeter.Lose(self: StreakMeter, lost: number, now: number): ()
	self.LostAt = now
	self.HiddenAt = nil
	local view = self.View
	view.Count.Text = `x{lost}`
	view.Puff.Visible = true
	view.Lost.Visible = true
end

function StreakMeter.Step(self: StreakMeter, now: number, scale: number): ()
	local view = self.View
	local center, size = self.Anchor()
	local losing = self.LostAt ~= nil and now - (self.LostAt :: number) < TUNING.LoseSeconds
	local fading = self.HiddenAt ~= nil and now - (self.HiddenAt :: number) < VANISH_SECONDS
	local active = self.Count > 0 or losing or fading
	if not center or not size or not active then
		view.Root.Visible = false
		if not losing then
			self.LostAt = nil
			view.Puff.Visible = false
			view.Lost.Visible = false
		end
		return
	end

	local parent = view.Root.Parent :: GuiObject
	local position = Vector2.new(center.X + size.X / 2 + TUNING.Gap * scale, center.Y) - parent.AbsolutePosition
	view.Root.Position = UDim2.fromOffset(position.X, position.Y)
	view.Root.Visible = true

	local tier = self.Tier
	local appear = Ease.OutBack((now - self.ShownAt) / APPEAR_SECONDS)
	local punch = 1 + PUNCH_SIZE * (1 - Ease.OutBack((now - self.PunchedAt) / PUNCH_SECONDS, 2))
	local vanish = if self.HiddenAt then 1 - Ease.Clamp((now - self.HiddenAt) / VANISH_SECONDS) else 1
	view.Scale.Scale = scale * appear * vanish

	local flicker = 1 + 0.05 * math.sin(now * FLICKER_FAST) + 0.03 * math.sin(now * FLICKER_SLOW)
	local snuff = 1
	if self.LostAt then
		local age = now - self.LostAt
		snuff = 1 - Ease.Clamp(age / VANISH_SECONDS)
		view.PuffScale.Scale = Ease.OutBack(age / 0.3, 1.5) * (1 + 0.2 * Ease.Clamp(age / TUNING.LoseSeconds))
		local fade = Ease.Clamp((age - 0.35) / (TUNING.LoseSeconds - 0.35))
		view.Puff.ImageTransparency = fade
		view.Lost.TextTransparency = fade
		view.LostStroke.Transparency = fade
		view.Lost.Position = UDim2.fromOffset(0, -12 - LOST_RISE * Ease.OutCubic(age / TUNING.LoseSeconds))
	end
	view.FlameScale.Scale = tier.Scale * flicker * punch * snuff
	view.Flame.Rotation = 4 * math.sin(now * FLICKER_SWAY)
	view.Glow.ImageTransparency = 0.35 + 0.15 * math.sin(now * 6) + 0.65 * (1 - snuff)
	view.Count.TextTransparency = 1 - snuff
	view.CountStroke.Transparency = 1 - snuff
	view.Bonus.TextTransparency = 1 - snuff
	view.BonusStroke.Transparency = 1 - snuff

	-- Embers drift off the tip, faster as the run grows.
	if self.Count > 0 and not self.LostAt and now >= self.EmberAt then
		self.EmberAt = now + TUNING.EmberSeconds / (1 + self.Count * 0.08)
		local flame = view.Flame
		self.Sparks:Embers(flame.AbsolutePosition + Vector2.new(flame.AbsoluteSize.X / 2, 0), 1, tier.Glow)
	end
end

function StreakMeter.Destroy(self: StreakMeter): ()
	self.View.Root:Destroy()
end

return StreakMeter
