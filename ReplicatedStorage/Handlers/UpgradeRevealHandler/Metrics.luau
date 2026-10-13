--!strict
-- One receipt size for the card layout and for the camera framing that keeps the subject above it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Configs.UpgradeReveal).Card
local TextScale = require(ReplicatedStorage.Shared.UI.TextScale)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

-- Sizes are logical pixels; the receipt draws them at `Scale` screen pixels each.
export type CardMetrics = {
	Scale: number,
	Density: number,
	Width: number,
	Height: number,
	Bottom: number,
	Narrow: boolean,
	-- The Skip control, grown to a touch target on touch screens, pushes the rows below it down by `Drop`.
	Skip: Vector2,
	Drop: number,
}

local Metrics = {}

--- The receipt inside `area`, the screen rectangle it is laid out in.
function Metrics.Card(area: Vector2): CardMetrics
	local camera = workspace.CurrentCamera
	local scale = TextScale.Screen(if camera then camera.ViewportSize else area)
	local logical = area / scale
	local density = math.clamp(logical.Y / Config.DensityHeight, Config.MinDensity, Config.MaxDensity)
	local width = math.min(Config.Width * density, logical.X - Config.Margin * 2)
	local narrow = width < Config.NarrowWidth
	local touch = if UserInputService.PreferredInput == Enum.PreferredInput.Touch
		then Theme.ScreenScale.MinTouchPixels / scale
		else 0
	local skip = Vector2.new(math.max(Config.SkipWidth, touch), math.max(Config.SkipHeight, touch))
	local drop = skip.Y - Config.SkipHeight
	return {
		Scale = scale,
		Density = density,
		Width = width,
		Height = drop + (if narrow then Config.NarrowHeight else math.max(Config.MinHeight, Config.Height * density)),
		Bottom = math.max(Config.MinBottom, Config.Bottom * density),
		Narrow = narrow,
		Skip = skip,
		Drop = drop,
	}
end

return Metrics
