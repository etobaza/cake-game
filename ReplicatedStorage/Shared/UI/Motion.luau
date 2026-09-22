--!strict
-- Spring presets. One place decides how the whole UI feels, so a screen asks for "Gentle" instead of
-- inventing its own numbers.
--
-- Flux springs take (frequency, damping): frequency is cycles per second, damping is a ratio where 1
-- settles without overshoot, below 1 bounces and above 1 drags. The presets are the tension/friction
-- pairs the design was tuned with, converted once:
--   frequency = sqrt(tension) / (2*pi)        damping = friction / (2 * sqrt(tension))

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)

--[[ Types ]]--
export type Preset = { Frequency: number, Damping: number }

--[[ Tables ]]--
local Motion = {}

Motion.Presets = {
	-- Overshoots hard. Rewards, level-ups, anything that should feel like a pop.
	Bubbly = { Frequency = 3.18, Damping = 0.35 },
	-- Quick and barely bouncy. Buttons, hovers.
	Responsive = { Frequency = 3.18, Damping = 0.6 },
	-- Eases in without overshoot. Panels sliding, bars filling.
	Gentle = { Frequency = 2.52, Damping = 0.95 },
	-- Slow and heavy. Long progress, ambient movement.
	Smooth = { Frequency = 3.18, Damping = 1.25 },
} :: { [string]: Preset }

--[[ Handling ]]--
--- A spring node started at `initial`, tuned by one of the presets above.
--- Write to it like any node and it animates instead of snapping.
function Motion.Spring<T>(initial: T, preset: Preset?): Flux.Node<T>
	local tuning = preset or Motion.Presets.Gentle
	return Flux.spring(initial, tuning.Frequency, tuning.Damping)
end

return Motion
