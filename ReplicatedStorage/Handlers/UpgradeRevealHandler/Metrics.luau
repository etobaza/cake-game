--!strict
-- One receipt size for the card layout and for the camera framing that keeps the subject above it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.UpgradeReveal).Card

export type CardMetrics = { Density: number, Width: number, Height: number, Bottom: number, Narrow: boolean }

local Metrics = {}

function Metrics.Card(viewport: Vector2): CardMetrics
	local density = math.clamp(viewport.Y / Config.DensityHeight, Config.MinDensity, Config.MaxDensity)
	local width = math.min(Config.Width * density, viewport.X - Config.Margin * 2)
	local narrow = width < Config.NarrowWidth
	return {
		Density = density,
		Width = width,
		Height = if narrow then Config.NarrowHeight else math.max(Config.MinHeight, Config.Height * density),
		Bottom = math.max(Config.MinBottom, Config.Bottom * density),
		Narrow = narrow,
	}
end

return Metrics
