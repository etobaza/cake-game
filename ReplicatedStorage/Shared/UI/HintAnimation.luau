--!strict
-- A small, manually stepped FSM owns the finger pose: Rest -> Press -> Hold -> Release.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]
--
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Ripple = require(ReplicatedStorage.Shared.Libs.Ripple)

--[[ Tables ]]
--
local HintAnimation = {}
HintAnimation.__index = HintAnimation

export type Animation = typeof(setmetatable(
	{} :: {
		Motion: Ripple.Motion<number>,
		Phase: Config.FingerPhase,
		Elapsed: number,
		Duration: number,
	},
	HintAnimation
))

--[[ Private Functions ]]
--
local function advance(self: Animation, remaining: number, period: number): number
	local phase = Config.FingerPhases[self.Phase]

	if self.Duration == 0 then
		self.Duration = math.max(Config.MinFingerPeriod, period) * phase.Fraction
		self.Motion:tween(phase.Pose, { duration = self.Duration, easing = "quintInOut" })
	end

	local elapsed = math.min(remaining, self.Duration - self.Elapsed)
	self.Motion:step(elapsed)
	self.Elapsed += elapsed

	if self.Elapsed >= self.Duration then
		self.Phase = phase.Next
		self.Elapsed = 0
		self.Duration = 0
	end

	return elapsed
end

--[[ Handling ]]
--
function HintAnimation.new(): Animation
	return setmetatable({
		Motion = Ripple.createMotion(0),
		Phase = "Rest" :: Config.FingerPhase,
		Elapsed = 0,
		Duration = 0,
	}, HintAnimation)
end

function HintAnimation.Step(self: Animation, delta: number, period: number): number
	-- Only the visible owner steps; suppressed hints retain their phase.
	local remaining = math.clamp(delta, 0, Config.MaxAnimationDelta)

	while remaining > 0 do
		remaining -= advance(self, remaining, period)
	end

	return math.clamp(self.Motion:getPosition(), 0, 1)
end

function HintAnimation.Reset(self: Animation): ()
	self.Motion:setPosition(0)
	self.Phase = "Rest"
	self.Elapsed = 0
	self.Duration = 0
end

function HintAnimation.Destroy(self: Animation): ()
	self.Motion:destroy()
end

return HintAnimation
