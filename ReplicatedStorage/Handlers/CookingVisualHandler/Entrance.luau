--!strict
-- Bakery entrance leaf visual: springs a door leaf between its server-supplied closed and open
-- pivots, carries a nested sign on the leaf, and rings one quiet chime a beat after the leaf starts
-- opening. The spring settles in about 0.65 s with under ~2% overshoot. Binding snaps to the current
-- server target without a chime, so a late join, shutdown or rebind never rings.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]
--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]
--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local CookingMotion = require(_Shared.Configs.CookingMotion)
local SoundPlayer = require(_Shared.SoundPlayer)
local Util = require(_Shared.CookingMotionUtil)

--[[ Constants ]]
--
local ENTRANCE = CookingMotion.Entrance
local TUNING = CookingMotion.EntranceMotion

export type EntranceVisual = Util.VisualEntry

--[[ Private helpers ]]
--
-- The sign is an optional Model nested directly under the leaf, recognised by its local pose
-- metadata. Only the leaf that owns the sign carries the pair's chime.
local function findSign(leaf: Model): Model?
	for _, child in leaf:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(ENTRANCE.SignClosedLocal) ~= nil then
			return child
		end
	end
	return nil
end

local function chimeParent(sign: Model?, leaf: Model): BasePart?
	if sign then
		local part = sign:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part
		end
	end
	return leaf.PrimaryPart or leaf:FindFirstChildWhichIsA("BasePart", true)
end

--[[ Factory ]]
--
local function new(leaf: Model): EntranceVisual
	local janitor = Janitor.new()
	local alive = true

	local initialized = false
	local opened = false
	local springPosition = 0
	local springVelocity = 0
	local sign: Model? = nil
	local chimeAt: number? = nil
	local lastPivot: CFrame? = nil

	local function applyPose(closed: CFrame, open: CFrame, alpha: number): ()
		-- Move the parent leaf first, then the sign relative to the leaf's new pivot, so both end in
		-- the correct world pose regardless of restore order.
		local hinge = Util.GetVector3(leaf, ENTRANCE.HingePosition)
		if not hinge then
			return
		end
		local axis, angle = (open.Rotation * closed.Rotation:Inverse()):ToAxisAngle()
		local leafPivot = CFrame.new(hinge) * CFrame.fromAxisAngle(axis, angle * alpha) * CFrame.new(-hinge) * closed
		if lastPivot ~= leafPivot then
			leaf:PivotTo(leafPivot)
			lastPivot = leafPivot
		end

		if not sign then
			return
		end
		local signClosed = Util.GetCFrame(sign, ENTRANCE.SignClosedLocal)
		local signOpen = Util.GetCFrame(sign, ENTRANCE.SignOpenLocal)
		if signClosed and signOpen then
			sign:PivotTo(leafPivot * signClosed:Lerp(signOpen, alpha))
		end
	end

	local function playChime(): ()
		local parent = chimeParent(sign, leaf)
		if alive and parent then
			local sound = SoundPlayer.Play("DoorBell", parent, TUNING.ChimePlaybackSpeed)
			janitor:Add(sound, "Destroy", "Chime")
		end
	end

	local function focus(): Vector3?
		return leaf:GetPivot().Position
	end

	local function step(context: Util.StepContext): ()
		local closed = Util.GetCFrame(leaf, ENTRANCE.ClosedPivot)
		local open = Util.GetCFrame(leaf, ENTRANCE.OpenPivot)
		if not closed or not open then
			return
		end

		if sign == nil then
			sign = findSign(leaf)
		end

		local cafeOpen = Util.GetBoolean(leaf, ENTRANCE.CafeOpen) == true
		local target = if cafeOpen then 1 else 0

		if not initialized then
			-- Snap to the current server target; never replay the opening on first binding.
			initialized = true
			opened = cafeOpen
			springPosition = target
			springVelocity = 0
			applyPose(closed, open, target)
			return
		end

		-- A fresh opening transition rings once; closing is silent.
		if cafeOpen and not opened and sign and not context.Culled and not context.Presenting then
			chimeAt = context.Now + TUNING.ChimeDelay
		elseif not cafeOpen or context.Culled or context.Presenting then
			chimeAt = nil
		end
		opened = cafeOpen
		if chimeAt and context.Now >= chimeAt then
			chimeAt = nil
			playChime()
		end

		if context.Culled then
			-- Keep the authoritative pose cheaply when far; no spring, no chime, no camera fight.
			springPosition = target
			springVelocity = 0
			applyPose(closed, open, target)
			return
		end

		local dt = math.min(context.Dt, TUNING.MaxStepSeconds)
		springPosition, springVelocity =
			Util.StepSpring(springPosition, springVelocity, target, TUNING.SpringStiffness, TUNING.SpringDamping, dt)
		if math.abs(springPosition - target) < 1e-4 and math.abs(springVelocity) < 1e-4 then
			springPosition, springVelocity = target, 0
		end
		applyPose(closed, open, springPosition)
	end

	local function destroy(): ()
		alive = false
		-- Restore the authored pose before handing the leaf back to the server/vacant view.
		if leaf.Parent ~= nil then
			local closed = Util.GetCFrame(leaf, ENTRANCE.ClosedPivot)
			local open = Util.GetCFrame(leaf, ENTRANCE.OpenPivot)
			if closed and open then
				applyPose(closed, open, 0)
			end
		end
		janitor:Destroy()
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
