--!strict
-- Shared math and attribute helpers for the cooking/entrance motion handler. It owns the one
-- authoritative time source, the pause-aware phase progress used by mixing and the oven clock, and
-- the bottom-anchored pose deformation reused by the mixer dough and the fresh-food squash. Keeping
-- these in one place avoids every private module re-deriving the same server-synced timing. It is
-- context-free, so the server OvenView reuses its pivot rotation too.

--[[ Services ]]
--
local Workspace = game:GetService("Workspace")

--[[ Tables ]]
--
local CookingMotionUtil = {}

--[[ Types ]]
--
-- One shared frame context, filled by the handler and passed to every tracked entry. The entries
-- never open their own connection or task; they only read this record each PreRender step.
export type StepContext = {
	Now: number,
	Dt: number,
	CameraPosition: Vector3,
	Presenting: boolean,
	Culled: boolean,
}

-- The factory contract every private visual module returns. Closures keep the per-object state and
-- its Janitor private, so the handler only holds this narrow record.
export type VisualEntry = {
	-- World point used for distance culling, or nil while the source has no resolvable pose yet.
	Focus: () -> Vector3?,
	Step: (context: StepContext) -> (),
	Destroy: () -> (),
}

--[[ Constants ]]
--
-- One full turn in radians, shared by the mixer orbit, the oven clock and the pop bounce.
CookingMotionUtil.TAU = math.pi * 2
-- A spring this close to its target, moving this slowly, has visibly settled and snaps to rest.
CookingMotionUtil.SPRING_SETTLE_EPSILON = 1e-4

local TAU = CookingMotionUtil.TAU

--[[ Time and progress ]]
--
-- The only clock the visuals trust. Server timestamps (PhaseStartedAt, MixStartedAt, CompletedAt)
-- are world GetServerTimeNow values, so the client samples the same world time and never keeps an
-- artificial elapsed timer that would drift after a pause or a late join.
function CookingMotionUtil.ServerNow(): number
	return Workspace:GetServerTimeNow()
end

-- Clamped phase progress with pause caps. `caps` holds optional freeze timestamps (HeatPausedAt for
-- fuel exhaustion, PausedAt for the day summary); a nonzero cap pulls the effective "now" back so a
-- paused batch freezes exactly where the server stopped it. Summary can therefore freeze the mixer
-- orbit and the oven hand on the same sample the server used.
function CookingMotionUtil.PhaseAlpha(startedAt: number, endsAt: number, caps: { number }, now: number): number
	local effective = now
	for _, cap in caps do
		if cap > 0 and cap < effective then
			effective = cap
		end
	end

	local span = endsAt - startedAt
	if span <= 0 then
		return 0
	end

	return math.clamp((effective - startedAt) / span, 0, 1)
end

--[[ Easing ]]
--
function CookingMotionUtil.Smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Smoothstep across an explicit window, clamped outside it.
function CookingMotionUtil.SmoothRange(value: number, edge0: number, edge1: number): number
	if edge1 <= edge0 then
		return if value >= edge1 then 1 else 0
	end
	return CookingMotionUtil.Smoothstep((value - edge0) / (edge1 - edge0))
end

-- A single decaying bounce that maps alpha 0 and 1 back to unit scale, so a finished dish can pop
-- without ever leaving a permanent deformation. Vertical stretch is paired with a matching
-- horizontal squash to read as a soft, volume-preserving bounce rather than a scale-up.
function CookingMotionUtil.PopScale(alpha: number, amplitude: number): Vector3
	alpha = math.clamp(alpha, 0, 1)
	local wobble = math.sin(alpha * TAU) * (1 - alpha) * amplitude
	return Vector3.new(1 - wobble * 0.5, 1 + wobble, 1 - wobble * 0.5)
end

--[[ Pose deformation ]]
--
-- Scale a part's local offset around a frame origin without touching its rotation. The cooking
-- frames are authored bottom-anchored (the model's bottom sits at the frame origin), so scaling the
-- offset about that origin keeps the dish planted on the surface while it grows or bounces.
function CookingMotionUtil.ScaleAboutFrame(frame: CFrame, offset: CFrame, scale: Vector3): CFrame
	local position = offset.Position
	local scaled = Vector3.new(position.X * scale.X, position.Y * scale.Y, position.Z * scale.Z)
	return frame * (CFrame.new(scaled) * (offset - position))
end

-- Resize one recorded part by `scale` and place it at its recorded offset scaled about `frame`.
-- `size` and `offset` are the part's unscaled size and its pose relative to the frame.
function CookingMotionUtil.ScalePartAboutFrame(
	part: BasePart,
	size: Vector3,
	offset: CFrame,
	frame: CFrame,
	scale: Vector3
): ()
	part.Size = size * scale
	part.CFrame = CookingMotionUtil.ScaleAboutFrame(frame, offset, scale)
end

-- Rotate a pivot about a world-space axis through its own position, keeping that point fixed. The
-- oven doors and the clock hand turn about their authored pivots this way.
function CookingMotionUtil.RotateAboutAxis(pivot: CFrame, axis: Vector3, angle: number): CFrame
	return CFrame.new(pivot.Position) * CFrame.fromAxisAngle(axis, angle) * pivot.Rotation
end

-- Semi-implicit damped spring step on a scalar. Returns the new position and velocity. Stiffness and
-- damping are chosen by the caller for the desired settle time and overshoot; the handler clamps dt
-- before calling so a long frame cannot make the integrator ring.
function CookingMotionUtil.StepSpring(
	position: number,
	velocity: number,
	target: number,
	stiffness: number,
	damping: number,
	dt: number
): (number, number)
	local acceleration = (target - position) * stiffness - velocity * damping
	local nextVelocity = velocity + acceleration * dt
	local nextPosition = position + nextVelocity * dt
	return nextPosition, nextVelocity
end

-- True once a spring sits on its target with no meaningful velocity left.
function CookingMotionUtil.IsSpringSettled(position: number, velocity: number, target: number): boolean
	return math.abs(position - target) < CookingMotionUtil.SPRING_SETTLE_EPSILON
		and math.abs(velocity) < CookingMotionUtil.SPRING_SETTLE_EPSILON
end

--[[ Attribute readers ]]
--
-- Server metadata arrives as dynamically typed attributes and can replicate a frame or two after the
-- object. These readers narrow the one genuine dynamic boundary and return nil until the value is
-- present and the expected type, letting callers retry on the shared scheduler instead of erroring.
function CookingMotionUtil.GetNumber(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

function CookingMotionUtil.GetString(instance: Instance, name: string): string?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" then value else nil
end

function CookingMotionUtil.GetBoolean(instance: Instance, name: string): boolean?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "boolean" then value else nil
end

function CookingMotionUtil.GetCFrame(instance: Instance, name: string): CFrame?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "CFrame" then value else nil
end

function CookingMotionUtil.GetVector3(instance: Instance, name: string): Vector3?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else nil
end

function CookingMotionUtil.GetColor3(instance: Instance, name: string): Color3?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "Color3" then value else nil
end

return CookingMotionUtil
