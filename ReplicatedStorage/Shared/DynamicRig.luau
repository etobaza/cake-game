--!strict
-- Script-animated world copies that render as dynamic objects.
--
-- Roblox caches shadows for still world geometry, and an anchored part that a script moves makes the cached shadows
-- around it re-render every frame: hundreds of extra draw calls inside a bakery. Parts in a Humanoid model render as
-- dynamic objects, like characters, and leave that cache alone. Each copy therefore hangs from an anchored root on a
-- kinematic AnimationConstraint and moves only through the joint's Transform.

local DynamicRig = {}
DynamicRig.__index = DynamicRig

export type DynamicRig = typeof(setmetatable(
	{} :: {
		Model: Model,
		Root: Part,
		Base: Attachment,
		Origin: CFrame,
		Joints: { [BasePart]: AnimationConstraint },
		Offsets: { [BasePart]: CFrame },
	},
	DynamicRig
))

function DynamicRig.new(name: string, origin: CFrame): DynamicRig
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.CFrame = origin
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	local base = Instance.new("Attachment")
	base.Parent = root

	return setmetatable({
		Model = model,
		Root = root,
		Base = base,
		Origin = origin,
		Joints = {},
		Offsets = {},
	}, DynamicRig)
end

-- Takes over a part where it stands; it holds that frame until the first Place.
function DynamicRig.Attach(self: DynamicRig, part: BasePart): ()
	local offset = part.CFrame:ToObjectSpace(self.Origin)
	local tip = Instance.new("Attachment")
	tip.CFrame = offset
	tip.Parent = part

	local joint = Instance.new("AnimationConstraint")
	joint.Attachment0 = self.Base
	joint.Attachment1 = tip
	joint.IsKinematic = true
	joint.Parent = part

	part.Anchored = false
	part.Parent = self.Model
	self.Joints[part] = joint
	self.Offsets[part] = offset
end

function DynamicRig.Place(self: DynamicRig, part: BasePart, frame: CFrame): ()
	self.Joints[part].Transform = self.Origin:ToObjectSpace(frame) * self.Offsets[part]
end

function DynamicRig.Destroy(self: DynamicRig): ()
	self.Model:Destroy()
	table.clear(self.Joints)
	table.clear(self.Offsets)
end

return DynamicRig
