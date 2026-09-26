--!strict
-- Solve the three R15 arm joints through the existing pose layer, preserving the seated body.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.GuestDining)
local JointPose = require(ReplicatedStorage.Shared.JointPose)

local REACH_EPSILON = 0.001
local PlateArm = {}
PlateArm.__index = PlateArm

export type PlateArm = typeof(setmetatable(
	{} :: {
		Torso: BasePart,
		Pose: JointPose.JointPose,
		Clip: JointPose.Clip,
		Side: string,
		GripToTip: CFrame,
		ElbowDirection: Vector3,
	},
	PlateArm
))

local function jointFrames(joint: Motor6D | AnimationConstraint): (CFrame?, CFrame?)
	if joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	end

	local first, second = joint.Attachment0, joint.Attachment1
	return if first then first.CFrame else nil, if second then second.CFrame else nil
end

local function segmentFrame(start: Vector3, finish: Vector3, normal: Vector3, pivot: Vector3): CFrame
	-- R15 arm segments extend along local -Y. Keep local +X on the elbow's outer side.
	local rotation = (CFrame.lookAt(start, finish, normal) * CFrame.Angles(math.pi / 2, 0, 0)).Rotation
	return CFrame.new(start - rotation:VectorToWorldSpace(pivot)) * rotation
end

function PlateArm.new(
	model: Model,
	torso: BasePart,
	side: string,
	gripToTip: CFrame,
	elbowDirection: Vector3
): PlateArm
	local clip: JointPose.Clip = { Duration = 1, Samples = {} }
	local mask = {
		[side .. "UpperArm"] = side .. "Shoulder",
		[side .. "LowerArm"] = side .. "Elbow",
		[side .. "Hand"] = side .. "Wrist",
	}

	for name in mask do
		clip.Samples[name] = { { Time = 0, Frame = CFrame.identity } }
	end

	return setmetatable({
		Torso = torso,
		Clip = clip,
		Side = side,
		GripToTip = gripToTip,
		ElbowDirection = elbowDirection,
		Pose = JointPose.new(model, clip, mask, Config.PoseFadeSeconds),
	}, PlateArm)
end

function PlateArm.Restore(self: PlateArm): ()
	self.Pose:Restore()
end

function PlateArm.Step(self: PlateArm, deltaTime: number, active: boolean, tipFrame: CFrame): ()
	local bindings = self.Pose.Bindings
	local side = self.Side
	local shoulder, elbow, wrist = bindings[side .. "UpperArm"], bindings[side .. "LowerArm"], bindings[side .. "Hand"]

	if not shoulder or not elbow or not wrist then
		return
	end

	local shoulderParent, shoulderChild = jointFrames(shoulder.Joint)
	local elbowParent, elbowChild = jointFrames(elbow.Joint)
	local wristParent, wristChild = jointFrames(wrist.Joint)

	if
		not shoulderParent
		or not shoulderChild
		or not elbowParent
		or not elbowChild
		or not wristParent
		or not wristChild
	then
		return
	end

	local torso = self.Torso.CFrame
	local hand = tipFrame * self.GripToTip:Inverse()
	local origin = (torso * shoulderParent).Position
	local desiredWrist = (hand * wristChild).Position
	local delta = desiredWrist - origin
	local upperLength = (elbowParent.Position - shoulderChild.Position).Magnitude
	local lowerLength = (wristParent.Position - elbowChild.Position).Magnitude

	if delta.Magnitude < REACH_EPSILON or math.min(upperLength, lowerLength) <= REACH_EPSILON then
		return
	end

	local distance = math.clamp(
		delta.Magnitude,
		math.abs(upperLength - lowerLength) + REACH_EPSILON,
		upperLength + lowerLength - REACH_EPSILON
	)
	local direction = delta.Unit
	local pole = torso:VectorToWorldSpace(self.ElbowDirection)
	local bend = pole - direction * pole:Dot(direction)

	if bend.Magnitude < REACH_EPSILON then
		bend = torso.LookVector - direction * torso.LookVector:Dot(direction)
	end

	if bend.Magnitude < REACH_EPSILON then
		return
	end

	bend = bend.Unit
	local along = (upperLength ^ 2 - lowerLength ^ 2 + distance ^ 2) / (2 * distance)
	local elbowPosition = origin + direction * along + bend * math.sqrt(math.max(0, upperLength ^ 2 - along ^ 2))
	local wristPosition = origin + direction * distance
	local normal = bend:Cross(direction).Unit
	local upper = segmentFrame(origin, elbowPosition, normal, shoulderChild.Position)
	local lower = segmentFrame(elbowPosition, wristPosition, normal, elbowChild.Position)
	hand += wristPosition - desiredWrist

	local samples = self.Clip.Samples
	samples[side .. "UpperArm"][1].Frame = shoulderParent:Inverse() * torso:ToObjectSpace(upper) * shoulderChild
	samples[side .. "LowerArm"][1].Frame = elbowParent:Inverse() * upper:ToObjectSpace(lower) * elbowChild
	samples[side .. "Hand"][1].Frame = wristParent:Inverse() * lower:ToObjectSpace(hand) * wristChild
	self.Pose:Step(deltaTime, active, 0, nil, nil, nil)
end

function PlateArm.Destroy(self: PlateArm): ()
	self.Pose:Destroy()
end

return PlateArm
