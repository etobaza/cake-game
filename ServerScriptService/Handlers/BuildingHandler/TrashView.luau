--!strict
-- A successful discard makes the authored trash bin squash and wobble once.
-- The animation is derived by BuildingHandler's shared tick; it owns no gameplay state or loop.

--[[ Constants ]]--
local ANIMATION_SECONDS = 0.7
local MAX_SQUASH = 0.13
local MAX_WOBBLE = math.rad(9)
local WOBBLE_TURNS = 2.5

--[[ Tables ]]--
local TrashView = {}
TrashView.__index = TrashView

export type TrashView = typeof(setmetatable(
	{} :: {
		Part: BasePart,
		OriginalCFrame: CFrame,
		OriginalSize: Vector3,
		StartedAt: number?,
	},
	TrashView
))

--[[ Private Functions ]]--
local function easeOut(value: number): number
	local inverse = 1 - value

	return 1 - inverse * inverse * inverse
end

--[[ Handling ]]--
function TrashView.new(_root: Instance, building: any): TrashView
	local self = setmetatable({}, TrashView) :: TrashView

	self.Part = building.Part
	self.OriginalCFrame = self.Part.CFrame
	self.OriginalSize = self.Part.Size
	self.StartedAt = nil

	return self
end

function TrashView.Play(self: TrashView): ()
	-- A second item restarts the reaction cleanly instead of stacking transforms.
	self.Part.CFrame = self.OriginalCFrame
	self.Part.Size = self.OriginalSize
	self.StartedAt = workspace:GetServerTimeNow()
end

function TrashView.Update(self: TrashView, _deltaTime: number, now: number): ()
	local startedAt = self.StartedAt
	if not startedAt then
		return
	end

	local progress = math.clamp((now - startedAt) / ANIMATION_SECONDS, 0, 1)
	if progress >= 1 then
		self.StartedAt = nil
		self.Part.CFrame = self.OriginalCFrame
		self.Part.Size = self.OriginalSize
		return
	end

	-- One broad squash reads as the item landing; the damped roll is the metal bin settling.
	local squash = math.sin(progress * math.pi) * MAX_SQUASH
	local widthScale = 1 + squash * 0.35
	local heightScale = 1 - squash
	local size = Vector3.new(
		self.OriginalSize.X * widthScale,
		self.OriginalSize.Y * heightScale,
		self.OriginalSize.Z * widthScale
	)
	local settle = 1 - easeOut(progress)
	local roll = math.sin(progress * math.pi * 2 * WOBBLE_TURNS) * settle * MAX_WOBBLE
	local bottomOffset = -(self.OriginalSize.Y - size.Y) / 2

	self.Part.Size = size
	self.Part.CFrame = self.OriginalCFrame * CFrame.new(0, bottomOffset, 0) * CFrame.Angles(0, 0, roll)
end

function TrashView.Destroy(self: TrashView): ()
	self.StartedAt = nil

	if self.Part.Parent then
		self.Part.CFrame = self.OriginalCFrame
		self.Part.Size = self.OriginalSize
	end
end

return TrashView
