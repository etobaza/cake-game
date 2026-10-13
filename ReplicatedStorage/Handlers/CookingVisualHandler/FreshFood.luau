--!strict
-- Fresh completion squash: a one-shot bottom-anchored bounce applied directly to the static server
-- food parts (CFrame and Size only; never material, color or tags). It runs once on a real
-- Mixing/Cooking -> Ready transition and restores the exact original transform at the end. A late
-- bind, a presentation, culling, a hidden source or a removed character discards the celebration
-- rather than replaying it, because the server stays the sole owner of cooking state.

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

--[[ Types ]]
--
type PartRecord = {
	Part: BasePart,
	OriginalCFrame: CFrame,
	OriginalSize: Vector3,
	Offset: CFrame,
	LastCFrame: CFrame,
	LastSize: Vector3,
}

export type FreshFoodVisual = Util.VisualEntry

--[[ Constants ]]
--
local FRESH = CookingMotion.Fresh
local TUNING = CookingMotion.FreshFood

--[[ Factory ]]
--
local function new(model: Model): FreshFoodVisual
	local frame: CFrame? = nil
	local completedAt: number? = nil
	local records: { PartRecord } = {}
	local done = false
	local initialized = false

	local function restore(): ()
		for _, record in records do
			if record.Part.Parent ~= nil then
				if record.Part.Size == record.LastSize then
					record.Part.Size = record.OriginalSize
				end
				if record.Part.CFrame == record.LastCFrame then
					record.Part.CFrame = record.OriginalCFrame
				end
			end
		end
	end

	local function focus(): Vector3?
		local pose = frame or Util.GetCFrame(model, FRESH.CompletionFrame)
		return if pose then pose.Position else nil
	end

	local function step(context: Util.StepContext): ()
		if done then
			return
		end
		if not initialized then
			local completed = Util.GetNumber(model, FRESH.CompletedAt)
			local pose = Util.GetCFrame(model, FRESH.CompletionFrame)
			if not completed or not pose then
				return
			end
			if context.Now - completed > TUNING.MaxBindAge then
				done = true
				return
			end
			for _, part in model:GetDescendants() do
				if not part:IsA("BasePart") then
					continue
				end
				table.insert(records, {
					Part = part,
					OriginalCFrame = part.CFrame,
					OriginalSize = part.Size,
					Offset = pose:ToObjectSpace(part.CFrame),
					LastCFrame = part.CFrame,
					LastSize = part.Size,
				})
			end
			if #records == 0 then
				return
			end
			frame, completedAt, initialized = pose, completed, true
		end

		-- Discard, never replay, when suppressed, culled, or the source has been hidden by another
		-- owner. Restoring keeps the geometry exact for whoever shows it next.
		local anchor = records[1]
		local hidden = anchor ~= nil and (anchor.Part.LocalTransparencyModifier >= 1 or anchor.Part.Transparency >= 1)
		if context.Presenting or context.Culled or hidden then
			done = true
			restore()
			return
		end

		local alpha = (context.Now - (completedAt :: number)) / TUNING.SquashSeconds
		if alpha >= 1 then
			done = true
			restore()
			return
		end

		local scale = Util.PopScale(alpha, TUNING.SquashAmplitude)
		local dough = Util.GetString(model, FRESH.FoodKind) == "Dough"
		local growth = if dough
			then 1
			else TUNING.DishStartScale + (1 - TUNING.DishStartScale) * Util.SmoothRange(
				alpha,
				0,
				TUNING.AppearFraction
			)
		scale *= growth
		local pose = (frame :: CFrame) + Vector3.yAxis * (math.sin(math.pi * alpha) ^ 2 * TUNING.HopHeight)
		for _, record in records do
			if record.Part.Parent ~= nil then
				record.Part.Size = record.OriginalSize * scale
				record.Part.CFrame = Util.ScaleAboutFrame(pose, record.Offset, scale)
				record.LastCFrame, record.LastSize = record.Part.CFrame, record.Part.Size
			end
		end
	end

	local function destroy(): ()
		-- On tag removal (including a batch becoming Burnt) or streaming out, hand back the exact
		-- original transform so FoodBurnHandler and the server state keep clean geometry.
		if not done then
			restore()
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
