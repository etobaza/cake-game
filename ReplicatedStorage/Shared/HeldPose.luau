--!strict
-- One masked arm layer per character. Known work blends directly with its hold; other actions release it.
-- The caller supplies shared frame callbacks; this class owns only character lifetime observers.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.CharacterAnimations)
local Appearance = require(ReplicatedStorage.Shared.CarriedAppearance)
local JointPose = require(ReplicatedStorage.Shared.JointPose)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local HeldPose = {}
HeldPose.__index = HeldPose

export type HeldPose = typeof(setmetatable(
	{} :: {
		Model: Model,
		Clips: { [string]: JointPose.Clip },
		Janitor: any,
		AnimatorJanitor: any,
		Animator: Animator?,
		Blocking: { [AnimationTrack]: boolean },
		Transitions: { [AnimationTrack]: string },
		Pose: JointPose.JointPose?,
		Name: string?,
		Holding: boolean,
	},
	HeldPose
))

--[[ Handling ]]--
function HeldPose.ReadClips(): { [string]: JointPose.Clip }
	local clips: { [string]: JointPose.Clip } = {}
	local assets = ReplicatedStorage:WaitForChild("Assets", Config.PoseAssetTimeout)
	local animations = assets and assets:WaitForChild("Animations", Config.PoseAssetTimeout)
	for name, definition in Config.Clips do
		local sequenceName = definition.PoseSequence or definition.TransitionSequence
		local hold = definition.TransitionHold and Config.Clips[definition.TransitionHold]
		local joints = definition.Joints or (hold and hold.Joints)
		if not sequenceName or not joints then
			continue
		end
		local sequence = animations and animations:WaitForChild(sequenceName, Config.PoseAssetTimeout)
		if not sequence or not sequence:IsA("KeyframeSequence") then
			print(`[HeldPose] Missing authored {sequenceName}`)
			continue
		end
		local clip = JointPose.Read(sequence, joints)
		if clip then
			clips[name] = clip
		end
	end
	return clips
end

function HeldPose.new(model: Model, clips: { [string]: JointPose.Clip }): HeldPose
	local self: HeldPose = setmetatable({
		Model = model,
		Clips = clips,
		Janitor = Janitor.new(),
		AnimatorJanitor = Janitor.new(),
		Blocking = {},
		Transitions = {},
		Holding = false,
	}, HeldPose)
	self.Janitor:Add(self.AnimatorJanitor, "Destroy")
	self.Janitor:Add(
		model.DescendantAdded:Connect(function(instance: Instance): ()
			if instance:IsA("Animator") then
				self:BindAnimator(instance)
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		model.DescendantRemoving:Connect(function(instance: Instance): ()
			if instance == self.Animator then
				self:BindAnimator(nil)
			end
		end),
		"Disconnect"
	)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	self:BindAnimator(humanoid and humanoid:FindFirstChildOfClass("Animator"))
	return self
end

function HeldPose.ObserveTrack(self: HeldPose, track: AnimationTrack): ()
	-- Core has numeric value 1000 despite being the lowest priority; never compare enum values.
	local priority = track.Priority
	local animation = track.Animation
	local id = animation and animation.AnimationId
	local blocks = priority == Enum.AnimationPriority.Action2
		or priority == Enum.AnimationPriority.Action3
		or priority == Enum.AnimationPriority.Action4
		or id == Config.Clips.Sweep.Id
		or id == Config.Clips.Interact.Id
	if not blocks or self.Blocking[track] then
		return
	end
	self.Blocking[track] = true
	for name, definition in Config.Clips do
		if definition.Id == id and definition.TransitionHold and self.Clips[name] then
			self.Transitions[track] = name
			break
		end
	end
	self.AnimatorJanitor:Add(
		track.Ended:Connect(function(): ()
			self.Blocking[track] = nil
			self.Transitions[track] = nil
			self.AnimatorJanitor:Remove(track)
		end),
		"Disconnect",
		track
	)
end

function HeldPose.BindAnimator(self: HeldPose, animator: Animator?): ()
	if self.Animator == animator then
		return
	end
	self.AnimatorJanitor:Cleanup()
	table.clear(self.Blocking)
	table.clear(self.Transitions)
	self.Animator = animator
	if not animator then
		return
	end
	self.AnimatorJanitor:Add(
		animator.AnimationPlayed:Connect(function(track: AnimationTrack): ()
			self:ObserveTrack(track)
		end),
		"Disconnect"
	)
	for _, track in animator:GetPlayingAnimationTracks() do
		self:ObserveTrack(track)
	end
end

function HeldPose.SetItem(self: HeldPose, item: Appearance.Item?): ()
	local name = Appearance.GetHold(item)
	self.Holding = name ~= nil
	-- Retain the previous layer while empty so Step can fade it out instead of snapping.
	if not name or name == self.Name then
		return
	end
	self.Janitor:Remove("Pose")
	self.Pose, self.Name = nil, name
	local clip, definition = self.Clips[name], Config.Clips[name]
	if not clip or not definition or not definition.Joints then
		return
	end
	self.Pose = JointPose.new(self.Model, clip, definition.Joints, Config.FadeTime)
	self.Janitor:Add(self.Pose, "Destroy", "Pose")
end

function HeldPose.Restore(self: HeldPose): ()
	if self.Pose then
		self.Pose:Restore()
	end
end

function HeldPose.Step(self: HeldPose, deltaTime: number, time: number): ()
	local pose = self.Pose
	if not pose then
		return
	end
	local humanoid = pose.Humanoid
	local blocked = false
	local workTrack: AnimationTrack? = nil
	local workClip: JointPose.Clip? = nil
	for track in self.Blocking do
		local name = self.Transitions[track]
		local definition = name and Config.Clips[name]
		if not name or not definition or definition.TransitionHold ~= self.Name then
			blocked = true
			break
		end
		if not workTrack or track.WeightCurrent > workTrack.WeightCurrent then
			workTrack, workClip = track, self.Clips[name]
		end
	end
	local active = Config.CarryEnabled
		and self.Holding
		and not blocked
		and humanoid ~= nil
		and humanoid.RigType == Config.RigType
		and humanoid.Health > 0
		and Config.GroundStates[humanoid:GetState()] == true
	-- Animator fades the body as usual. This arm goes directly hold <-> work, never through Idle.
	pose:Step(
		deltaTime,
		active,
		time,
		workClip,
		if workTrack then workTrack.TimePosition else nil,
		if workTrack then workTrack.WeightCurrent else nil
	)
end

function HeldPose.Destroy(self: HeldPose): ()
	self.Janitor:Destroy()
	table.clear(self.Blocking)
	table.clear(self.Transitions)
	self.Pose, self.Animator = nil, nil
end

return HeldPose
