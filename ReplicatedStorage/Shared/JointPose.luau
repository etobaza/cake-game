--!strict
-- A visual overlay for selected R15 joints, sampled from an authored linear KeyframeSequence.
-- The owner restores the previous base before Animator evaluation, then applies this pose after it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Types ]]--
type Joint = Motor6D | AnimationConstraint
type Sample = { Time: number, Frame: CFrame }
type Binding = { Joint: Joint, Base: CFrame?, Written: CFrame? }
export type Clip = { Duration: number, Samples: { [string]: { Sample } } }

--[[ Tables ]]--
local JointPose = {}
JointPose.__index = JointPose

export type JointPose = typeof(setmetatable(
	{} :: {
		Model: Model,
		Clip: Clip,
		Mask: { [string]: string },
		Bindings: { [string]: Binding },
		Watching: { [Instance]: boolean },
		Humanoid: Humanoid?,
		Janitor: any,
		Weight: number,
		FadeTime: number,
	},
	JointPose
))

--[[ Private Functions ]]--
local function appendSample(clip: Clip, pose: Pose, time: number): boolean
	if pose.EasingStyle ~= Enum.PoseEasingStyle.Linear then
		warn("[JointPose] Carry sequence must be baked to linear samples")
		return false
	end
	local samples = clip.Samples[pose.Name]
	samples[#samples + 1] = { Time = time, Frame = pose.CFrame }
	return true
end

local function sampleAt(samples: { Sample }, time: number): CFrame
	local lower, upper = 1, #samples
	while lower < upper do
		local middle = math.ceil((lower + upper) / 2)
		if samples[middle].Time <= time then
			lower = middle
		else
			upper = middle - 1
		end
	end
	local first, second = samples[lower], samples[math.min(lower + 1, #samples)]
	local span = second.Time - first.Time
	local alpha = if span > 0 then math.clamp((time - first.Time) / span, 0, 1) else 0
	return first.Frame:Lerp(second.Frame, alpha)
end

-- Both joint classes expose Transform, but a property write needs a single class to type-check.
local function writeTransform(joint: Joint, frame: CFrame): ()
	local writable = joint :: any
	writable.Transform = frame
end

local function restoreBinding(binding: Binding): ()
	-- Another animation owner may already have updated this joint; never replace its fresh result.
	if binding.Base and binding.Written and binding.Joint.Parent and binding.Joint.Transform == binding.Written then
		writeTransform(binding.Joint, binding.Base)
	end
	binding.Base, binding.Written = nil, nil
end

--[[ Handling ]]--
function JointPose.Read(sequence: KeyframeSequence, mask: { [string]: string }): Clip?
	local frames: { Keyframe } = sequence:GetKeyframes() :: any
	table.sort(frames, function(first: Keyframe, second: Keyframe): boolean
		return first.Time < second.Time
	end)
	if #frames < 2 or frames[#frames].Time <= 0 then
		warn("[JointPose] Carry sequence needs at least two timed keyframes")
		return nil
	end
	local clip: Clip = { Duration = frames[#frames].Time, Samples = {} }
	for partName in mask do
		clip.Samples[partName] = {}
	end
	for _, frame in frames do
		for _, pose in frame:GetDescendants() do
			if not pose:IsA("Pose") or not mask[pose.Name] or pose.Weight <= 0 then
				continue
			end
			if not appendSample(clip, pose, frame.Time) then
				return nil
			end
		end
	end
	for partName, samples in clip.Samples do
		if #samples ~= #frames then
			warn(`[JointPose] Incomplete carry samples for {partName}`)
			return nil
		end
	end
	return clip
end

function JointPose.new(model: Model, clip: Clip, mask: { [string]: string }, fadeTime: number): JointPose
	local self: JointPose = setmetatable({
		Model = model,
		Clip = clip,
		Mask = mask,
		Bindings = {},
		Watching = {},
		Janitor = Janitor.new(),
		Weight = 0,
		FadeTime = fadeTime,
	}, JointPose)
	self.Janitor:Add(
		model.DescendantAdded:Connect(function(instance: Instance): ()
			self:Observe(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		model.DescendantRemoving:Connect(function(instance: Instance): ()
			self:Forget(instance)
		end),
		"Disconnect"
	)
	for _, instance in model:GetDescendants() do
		self:Observe(instance)
	end
	return self
end

function JointPose.Observe(self: JointPose, instance: Instance): ()
	if instance:IsA("Humanoid") then
		self.Humanoid = instance
		return
	end
	if not instance:IsA("Motor6D") and not instance:IsA("AnimationConstraint") then
		return
	end
	-- R15's motor and constraint rigs share joint names. Never bind a joint outside the configured arm.
	for partName, jointName in self.Mask do
		if instance.Name ~= jointName then
			continue
		end
		-- Streaming may deliver the joint before its endpoint reference.
		if not self.Watching[instance] then
			self:WatchJoint(instance)
		end
		local part = if instance:IsA("Motor6D")
			then instance.Part1
			else instance.Attachment1 and instance.Attachment1.Parent
		local previous = self.Bindings[partName]
		if previous and previous.Joint == instance then
			restoreBinding(previous)
			self.Bindings[partName] = nil
		end
		if part and part.Name == partName then
			if previous then
				restoreBinding(previous)
			end
			self.Bindings[partName] = { Joint = instance }
		end
	end
end

function JointPose.WatchJoint(self: JointPose, joint: Joint): ()
	self.Watching[joint] = true
	local property = if joint:IsA("Motor6D") then "Part1" else "Attachment1"
	self.Janitor:Add(
		joint:GetPropertyChangedSignal(property):Connect(function(): ()
			self:Observe(joint)
		end),
		"Disconnect",
		joint
	)
end

function JointPose.Forget(self: JointPose, instance: Instance): ()
	if instance == self.Humanoid then
		self.Humanoid = nil
	end
	if self.Watching[instance] then
		self.Janitor:Remove(instance)
		self.Watching[instance] = nil
	end
	for partName, binding in self.Bindings do
		if binding.Joint ~= instance then
			continue
		end
		restoreBinding(binding)
		self.Bindings[partName] = nil
	end
end

function JointPose.Restore(self: JointPose): ()
	for _, binding in self.Bindings do
		restoreBinding(binding)
	end
end

function JointPose.Step(
	self: JointPose,
	deltaTime: number,
	active: boolean,
	time: number,
	transition: Clip?,
	transitionTime: number?,
	transitionWeight: number?
): ()
	local target = if active then 1 else 0
	local step = deltaTime / math.max(self.FadeTime, 0.001)
	self.Weight += math.clamp(target - self.Weight, -step, step)
	if self.Weight <= 0 then
		return
	end
	local phase = time % self.Clip.Duration
	for partName, binding in self.Bindings do
		if not binding.Joint.Parent then
			continue
		end
		local base = binding.Joint.Transform
		local targetFrame = sampleAt(self.Clip.Samples[partName], phase)
		local workSamples = transition and transition.Samples[partName]
		if transition and workSamples then
			local workTime = math.clamp(transitionTime or 0, 0, transition.Duration)
			targetFrame = targetFrame:Lerp(sampleAt(workSamples, workTime), math.clamp(transitionWeight or 0, 0, 1))
		end
		local frame = base:Lerp(targetFrame, self.Weight)
		binding.Base = base
		writeTransform(binding.Joint, frame)
		-- Engine properties can round the CFrame on assignment; compare against the stored value.
		binding.Written = binding.Joint.Transform
	end
end

function JointPose.Destroy(self: JointPose): ()
	self:Restore()
	self.Janitor:Destroy()
	table.clear(self.Bindings)
	table.clear(self.Watching)
end

return JointPose
