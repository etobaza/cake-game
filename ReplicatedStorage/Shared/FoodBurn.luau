--!strict
-- The original material operates in linear RGB, not directly on sRGB texture bytes.
local Config = require(script.Parent.Configs.FoodBurn)
local FoodBurn = {}

export type State = {
	State: string,
	PhaseStartedAt: number?,
	BurnAt: number?,
	HeatPausedAt: number?,
}

function FoodBurn.ToLinear(value: number): number
	return if value <= 0.04045 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
end

function FoodBurn.ToSRGB(value: number): number
	value = math.clamp(value, 0, 1)
	return if value <= 0.0031308 then value * 12.92 else 1.055 * value ^ (1 / 2.4) - 0.055
end

local function overlay(value: number, twiceTint: number): number
	return if value >= 0.5 then 1 - (1 - value) * (2 - twiceTint) else value * twiceTint
end

function FoodBurn.Target(linear: Color3): Color3
	local tint = Config.OverlayDouble
	local color = Vector3.new(overlay(linear.R, tint.X), overlay(linear.G, tint.Y), overlay(linear.B, tint.Z))
	local gray = color:Dot(Config.GrayWeights)
	color = color:Lerp(Vector3.one * gray, Config.Desaturation)
	return Color3.new(color.X, color.Y, color.Z)
end

function FoodBurn.Color(original: Color3, fade: number): Color3
	local linear =
		Color3.new(FoodBurn.ToLinear(original.R), FoodBurn.ToLinear(original.G), FoodBurn.ToLinear(original.B))
	local color = linear:Lerp(FoodBurn.Target(linear), math.clamp(fade, 0, 1))
	return Color3.new(FoodBurn.ToSRGB(color.R), FoodBurn.ToSRGB(color.G), FoodBurn.ToSRGB(color.B))
end

function FoodBurn.Fade(state: State, now: number): number
	if state.State == "Burnt" then
		return 1
	end
	local started, ends = state.PhaseStartedAt or 0, state.BurnAt or 0
	if state.State ~= "Ready" or started <= 0 or ends <= started then
		return 0
	end
	if (state.HeatPausedAt or 0) > 0 then
		now = math.min(now, state.HeatPausedAt :: number)
	end
	local progress = (now - started) / (ends - started)
	local alpha = math.clamp((progress - Config.StartFraction) / (Config.EndFraction - Config.StartFraction), 0, 1)
	-- Unreal's cubic curve with zero arrival/departure tangents is smoothstep.
	return alpha * alpha * (3 - 2 * alpha)
end

return FoodBurn
