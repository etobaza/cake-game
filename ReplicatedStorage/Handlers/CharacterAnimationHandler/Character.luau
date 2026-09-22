--!strict
-- Ground locomotion is an event-driven FSM. Successful work uses separate animation tracks.
-- TrayHandler owns the arm-only carrying overlay for every visible character.
-- Default Animate remains responsible for jumping, falling, climbing and swimming.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Appearance = require(_Shared.CarriedAppearance)
local Config = require(_Shared.Configs.CharacterAnimations)
local FoodConfig = require(_Shared.Configs.FoodPresentation)
local GardenConfig = require(_Shared.Configs.Garden)
local VFXConfig = require(_Shared.Configs.VFX)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local StateMachine = require(_Shared.Libs.StateMachine)

--[[ Tables ]]--
local Character = {}
Character.__index = Character

export type Character = typeof(setmetatable(
	{} :: {
		Player: Player,
		Model: Model,
		Janitor: any,
		Tracks: { [string]: AnimationTrack },
		Humanoid: Humanoid?,
		Machine: any,
		Speed: number,
		Bound: boolean,
		Destroyed: boolean,
		Mixing: boolean,
	},
	Character
))

--[[ Private Functions ]]--
local function loadTrack(self: Character, animator: Animator, name: string, clip: Config.Clip): ()
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = clip.Id
	self.Janitor:Add(animation, "Destroy")
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn(`[CharacterAnimationHandler] Cannot load {name}: {track}`)
		return
	end
	if self.Destroyed then
		track:Destroy()
		return
	end
	track.Priority = clip.Priority
	track.Looped = clip.Looped
	self.Tracks[name] = track
	self.Janitor:Add(track, "Destroy")
end

local function makeMovementState(self: Character, name: string): any
	return {
		onEnter = function(): ()
			local track = self.Tracks[name]
			if track then
				track:Play(Config.FadeTime)
			end
		end,
		onExit = function(): ()
			local track = self.Tracks[name]
			if track then
				track:Stop(Config.FadeTime)
			end
		end,
	}
end

local function isGrounded(self: Character): boolean
	local humanoid = self.Humanoid
	return humanoid ~= nil and humanoid.Health > 0 and Config.GroundStates[humanoid:GetState()] == true
end

local function canAct(self: Character, action: Config.Action, item: Appearance.Item?): boolean
	local humanoid = self.Humanoid
	if not humanoid or self.Mixing or not isGrounded(self) then
		return false
	end
	if action.CancelOnMove and humanoid.MoveDirection.Magnitude > Config.MovingThreshold then
		return false
	end
	return action.ToolId == nil or (item ~= nil and item.Kind == "Tool" and item.Id == action.ToolId)
end

local function turnToWater(self: Character, dt: number): ()
	local humanoid = self.Humanoid
	local untilTime = self.Model:GetAttribute(VFXConfig.WaterUntilAttribute)
	local target = self.Model:GetAttribute(VFXConfig.WaterTargetAttribute)
	local brushUntil = self.Model:GetAttribute(GardenConfig.BrushUntilAttribute)
	local brushTarget = self.Model:GetAttribute(GardenConfig.BrushTargetAttribute)
	if typeof(brushUntil) == "number" and typeof(brushTarget) == "CFrame" then
		untilTime, target = brushUntil, brushTarget.Position
	end
	local root = humanoid and humanoid.RootPart
	if
		not humanoid
		or not root
		or humanoid.Health <= 0
		or humanoid.Sit
		or typeof(untilTime) ~= "number"
		or untilTime <= workspace:GetServerTimeNow()
		or typeof(target) ~= "Vector3"
	then
		return
	end
	local position = root.Position
	local facing = Vector3.new(target.X, position.Y, target.Z)
	if (facing - position).Magnitude < 0.001 then
		return
	end
	-- The local character owns its physics. Preserve position and let the server own the work lock.
	root.CFrame = root.CFrame:Lerp(CFrame.lookAt(position, facing), 1 - math.exp(-GardenConfig.WaterTurnSpeed * dt))
end

--[[ Handling ]]--
function Character.new(player: Player, model: Model): Character
	local self: Character = setmetatable({
		Player = player,
		Model = model,
		Janitor = Janitor.new(),
		Tracks = {},
		Speed = 0,
		Bound = false,
		Destroyed = false,
		Mixing = false,
	}, Character)
	-- A character arrives before its Humanoid/Animator on slow replication. No yielding spawn task.
	self.Janitor:Add(
		model.DescendantAdded:Connect(function(): ()
			self:TryBind()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		model.AncestryChanged:Connect(function(): ()
			self:TryBind()
		end),
		"Disconnect"
	)
	self:TryBind()
	return self
end

function Character.TryBind(self: Character): ()
	if self.Bound or self.Destroyed or not self.Model:IsDescendantOf(workspace) then
		return
	end
	local humanoid = self.Model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return
	end
	self.Bound = true
	self.Humanoid = humanoid
	self.Janitor:Add(
		RunService.Heartbeat:Connect(function(dt: number): ()
			turnToWater(self, dt)
		end),
		"Disconnect"
	)
	if humanoid.RigType ~= Config.RigType then
		warn("[CharacterAnimationHandler] Supplied animations require R15; keeping default animations")
		return
	end
	for name, clip in Config.Clips do
		if not clip.PoseSequence then
			loadTrack(self, animator, name, clip)
		end
	end
	if self.Destroyed then
		return
	end
	local root = humanoid.RootPart
	if root then
		self.Speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	end
	self.Machine = StateMachine.new({
		initialState = "Default",
		states = {
			Default = {},
			Idle = makeMovementState(self, "Idle"),
			Walk = makeMovementState(self, "Walk"),
			Run = makeMovementState(self, "Run"),
		},
	})
	self.Janitor:Add(self.Machine.onStateChange, "Destroy")
	self.Janitor:Add(
		humanoid.Running:Connect(function(speed: number): ()
			self.Speed = speed
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		humanoid.StateChanged:Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		humanoid.Died:Connect(function(): ()
			self:Destroy()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		self.Model:GetAttributeChangedSignal(Config.RunningAttribute):Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		self.Player:GetAttributeChangedSignal(FoodConfig.HandAttribute):Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self:Refresh()
end

function Character.Refresh(self: Character): ()
	local humanoid = self.Humanoid
	if self.Destroyed or not humanoid or not self.Machine then
		return
	end
	local grounded = isGrounded(self)
	local moving = grounded and humanoid.WalkSpeed > 0 and self.Speed > Config.MovingThreshold
	local movement = if not grounded then "Default" else "Idle"
	if moving then
		movement = if self.Model:GetAttribute(Config.RunningAttribute) then "Run" else "Walk"
	end
	self.Machine:SetState(movement)
	local clip, track = Config.Clips[movement], self.Tracks[movement]
	if track and clip and clip.ReferenceSpeed then
		track:AdjustSpeed(
			math.clamp(self.Speed / clip.ReferenceSpeed, Config.MinPlaybackSpeed, Config.MaxPlaybackSpeed)
		)
	end
	local item = Appearance.Decode(self.Player:GetAttribute(FoodConfig.HandAttribute))
	local interact = self.Tracks.Interact
	local working = grounded and self.Mixing
	if interact and working ~= interact.IsPlaying then
		if working then
			interact:Play(Config.FadeTime)
		else
			interact:Stop(Config.FadeTime)
		end
	end
	-- Full-body work cannot continue over locomotion or after returning its tool.
	for name, action in Config.Actions do
		local actionTrack = self.Tracks[name]
		if actionTrack and actionTrack.IsPlaying and not canAct(self, action, item) then
			actionTrack:Stop(Config.FadeTime)
		end
	end
end

function Character.SetMixing(self: Character, mixing: boolean): ()
	self.Mixing = mixing
	self:Refresh()
end

function Character.PlayAction(self: Character, action: string): ()
	local definition = Config.Actions[action]
	if self.Destroyed or not definition then
		return
	end
	local item = Appearance.Decode(self.Player:GetAttribute(FoodConfig.HandAttribute))
	if not canAct(self, definition, item) then
		return
	end
	local track = self.Tracks[action]
	if not track then
		return
	end
	-- One accepted action is one authored cycle, even if the uploaded asset loops.
	for name in Config.Actions do
		local other = self.Tracks[name]
		if name ~= action and other and other.IsPlaying then
			other:Stop(Config.FadeTime)
		end
	end
	track:Play(Config.FadeTime)
	track.TimePosition = 0
end

function Character.Destroy(self: Character): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, track in self.Tracks do
		track:Stop(0)
	end
	self.Janitor:Destroy()
	table.clear(self.Tracks)
end

return Character
