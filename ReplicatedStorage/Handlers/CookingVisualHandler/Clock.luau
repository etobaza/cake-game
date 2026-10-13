--!strict
-- Oven ClockHand visual: rotates the authored hand around its spindle to follow the server-owned
-- cooking/ready phase, sampled from world time so a fuel pause or the day summary freezes it. It
-- never touches the hand's size, material, transparency, surface or the server-owned dial, and it
-- only writes a pivot when the angle actually changes.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]
--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]
--
local CookingMotion = require(_Shared.Configs.CookingMotion)
local Util = require(_Shared.CookingMotionUtil)

--[[ Constants ]]
--
local TAU = math.pi * 2
local CLOCK = CookingMotion.Clock
local STATE = CookingMotion.State
-- Below this change the rotation is not worth a PivotTo; also used to tell "moved" from "at rest".
local ANGLE_EPSILON = 1e-4

export type ClockVisual = Util.VisualEntry

--[[ Private helpers ]]
--
-- Fraction of the current revolution, 0 at the phase start and 1 at its deadline. Cooking runs to
-- ReadyAt, Ready runs the ready-to-burn revolution to BurnAt, Burnt holds full, and every other
-- state rests. HeatPausedAt and PausedAt cap the sample so a paused hand stops exactly in place.
local function phaseFraction(hand: BasePart, now: number): number
	local state = Util.GetString(hand, CLOCK.StationState)
	if state == STATE.Burnt then
		return 1
	end

	local started = Util.GetNumber(hand, CLOCK.PhaseStartedAt)
	if not started then
		return 0
	end

	local deadline: number?
	if state == STATE.Cooking then
		deadline = Util.GetNumber(hand, CLOCK.ReadyAt)
	elseif state == STATE.Ready then
		deadline = Util.GetNumber(hand, CLOCK.BurnAt)
	end
	if not deadline then
		return 0
	end

	local heatPausedAt = Util.GetNumber(hand, CLOCK.HeatPausedAt) or 0
	local pausedAt = Util.GetNumber(hand, CLOCK.PausedAt) or 0
	return Util.PhaseAlpha(started, deadline, { heatPausedAt, pausedAt }, now)
end

--[[ Factory ]]
--
local function new(hand: BasePart): ClockVisual
	local lastAngle: number? = nil

	local function focus(): Vector3?
		return hand.Position
	end

	local function step(context: Util.StepContext): ()
		-- Missing metadata never destroys the object; it idles and retries on the shared scheduler.
		local rest = Util.GetCFrame(hand, CLOCK.RestPivot)
		local axis = Util.GetVector3(hand, CLOCK.Axis)
		if not rest or not axis then
			return
		end

		-- A far oven freezes its hand; the authoritative pose catches up when it is back in range.
		if context.Culled then
			return
		end

		local angle = phaseFraction(hand, context.Now) * TAU
		if lastAngle ~= nil and math.abs(angle - lastAngle) < ANGLE_EPSILON then
			return
		end

		hand:PivotTo(CFrame.new(rest.Position) * CFrame.fromAxisAngle(axis, angle) * rest.Rotation)
		lastAngle = angle
	end

	local function destroy(): ()
		-- Restore the resting pose on untrack, unless the source is gone. The server does not rotate
		-- the hand while active, so rest is the correct handoff state.
		if lastAngle == nil or hand.Parent == nil then
			return
		end
		local rest = Util.GetCFrame(hand, CLOCK.RestPivot)
		if rest then
			hand:PivotTo(rest)
		end
	end

	return {
		Focus = focus,
		Step = step,
		Destroy = destroy,
	}
end

return {
	new = new,
}
