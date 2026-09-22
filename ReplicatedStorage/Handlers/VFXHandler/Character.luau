--!strict
-- Ground dust, nozzle water and accepted sweep timing for one visible character.
--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local AnimationConfig = require(ReplicatedStorage.Shared.Configs.CharacterAnimations)
local Config = require(ReplicatedStorage.Shared.Configs.VFX)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Effect = require(script.Parent.Effect)

--[[ Tables ]]--
local Character = {}
Character.__index = Character
export type Character = typeof(setmetatable(
	{} :: {
		Model: Model,
		Root: Folder,
		Templates: { [string]: BasePart },
		Janitor: any,
		Body: BasePart?,
		Humanoid: Humanoid?,
		Animator: Animator?,
		Run: Effect.Effect?,
		Water: Effect.Effect?,
		Sweep: Effect.Effect?,
		WaterTool: BasePart?,
		SweepTrack: AnimationTrack?,
		AuthorizedUntil: number,
		SweepPassed: { [string]: boolean },
	},
	Character
))

--[[ Private Functions ]]--
local function isSweep(track: AnimationTrack): boolean
	local animation: Animation? = track.Animation
	return animation ~= nil and animation.AnimationId == AnimationConfig.Clips.Sweep.Id
end

local function aimWater(effect: Effect.Effect, target: Vector3): ()
	local emitter = effect.Emitters[1]
	local mouth = emitter and emitter.Object.Parent
	if mouth and mouth:IsA("Attachment") then
		local flight = Config.WaterFlightSeconds
		local velocity = (target - mouth.WorldPosition - Config.WaterGravity * flight * flight / 2) / flight
		mouth.WorldCFrame = CFrame.lookAt(mouth.WorldPosition, mouth.WorldPosition + velocity)
		for _, entry in effect.Emitters do
			entry.Object.Acceleration = Config.WaterGravity
			entry.Object.Speed = NumberRange.new(velocity.Magnitude)
			entry.Object.Lifetime = NumberRange.new(flight)
		end
	end
	for _, beam in effect.Beams do
		local nozzle, landing = beam.Attachment0, beam.Attachment1
		if not nozzle or not landing then
			continue
		end
		local delta = target - nozzle.WorldPosition
		local horizontal = delta * Vector3.new(1, 0, 1)
		if horizontal.Magnitude < 0.001 then
			continue
		end
		nozzle.WorldAxis = horizontal.Unit
		landing.WorldPosition = target
		landing.WorldAxis = -Vector3.yAxis
		beam.CurveSize0 = horizontal.Magnitude / 3
		beam.CurveSize1 = math.max(0, -delta.Y) / 3
	end
end

--[[ Handling ]]--
function Character.new(model: Model, root: Folder, templates: { [string]: BasePart }): Character
	local self: Character = setmetatable({
		Model = model,
		Root = root,
		Templates = templates,
		Janitor = Janitor.new(),
		AuthorizedUntil = 0,
		SweepPassed = {},
	}, Character)
	self.Janitor:Add(
		model.DescendantAdded:Connect(function(): ()
			self:Resolve()
		end),
		"Disconnect"
	)
	self:Resolve()
	return self
end

function Character.Resolve(self: Character): ()
	self.Body = self.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Humanoid = self.Model:FindFirstChildOfClass("Humanoid")
	local animator = self.Humanoid and self.Humanoid:FindFirstChildOfClass("Animator")
	if not animator or animator == self.Animator then
		return
	end
	self.Animator = animator
	self.Janitor:Add(
		animator.AnimationPlayed:Connect(function(track: AnimationTrack): ()
			if isSweep(track) and workspace:GetServerTimeNow() <= self.AuthorizedUntil then
				self:StartSweep(track)
			end
		end),
		"Disconnect",
		"Animator"
	)
end

function Character.StartSweep(self: Character, track: AnimationTrack): ()
	self.SweepTrack = track
	table.clear(self.SweepPassed)
	if self.Sweep then
		self.Sweep:Cancel(workspace:GetServerTimeNow())
	end
end

function Character.AuthorizeSweep(self: Character, time: number): ()
	self.AuthorizedUntil = time + Config.SweepWait
	if not self.Animator then
		return
	end
	for _, track in self.Animator:GetPlayingAnimationTracks() do
		if isSweep(track) then
			self:StartSweep(track)
			return
		end
	end
end

function Character.GetEffect(self: Character, name: string, scale: number?): Effect.Effect?
	local template = self.Templates[name]
	if not template then
		return nil
	end
	local effect = Effect.new(template, self.Root, scale)
	self.Janitor:Add(effect, "Destroy", name)
	return effect
end

function Character.UpdateWater(self: Character, tool: BasePart?, now: number, active: boolean): ()
	if self.WaterTool ~= tool then
		self.Janitor:Remove("Water")
		self.Water, self.WaterTool = nil, tool
	end
	local untilTime = self.Model:GetAttribute(Config.WaterUntilAttribute)
	local target = self.Model:GetAttribute(Config.WaterTargetAttribute)
	local watering = active
		and tool ~= nil
		and tool.Parent ~= nil
		and tool:GetAttribute("ToolId") == "watering_can"
		and typeof(untilTime) == "number"
		and untilTime > now
		and typeof(target) == "Vector3"
	if watering and not self.Water and tool then
		local template = self.Templates.Water
		local size = template and template:GetAttribute("SourceToolSize")
		local scale = if typeof(size) == "Vector3" then tool.Size.Z / size.Z else 1
		self.Water = self:GetEffect("Water", scale)
	end
	if not self.Water then
		return
	end
	self.Water:SetEnabled(watering, now)
	if tool then
		self.Water:Step(tool.CFrame, now)
	end
	if watering and typeof(target) == "Vector3" then
		aimWater(self.Water, target)
	end
end

function Character.UpdateSweep(self: Character, frame: CFrame, tool: BasePart?, now: number, active: boolean): ()
	local track = self.SweepTrack
	local valid = active
		and track ~= nil
		and track.IsPlaying
		and tool ~= nil
		and tool.Parent ~= nil
		and tool:GetAttribute("ToolId") == "broom"
	if not valid then
		if track then
			self.SweepTrack = nil
			if self.Sweep then
				self.Sweep:Cancel(now)
			end
		end
	elseif track and track.Length > 0 then
		local fraction = track.TimePosition / track.Length
		for _, phase in Config.SweepPhases do
			if fraction < phase.Fraction or self.SweepPassed[phase.Group] then
				continue
			end
			self.SweepPassed[phase.Group] = true
			if not self.Sweep then
				self.Sweep = self:GetEffect("Sweep")
			end
			if self.Sweep then
				self.Sweep:Burst(now, phase.Group)
			end
		end
	end
	if self.Sweep then
		local offset = self.Sweep.Part:GetAttribute("SourceOffset")
		self.Sweep:Step(frame * (if typeof(offset) == "CFrame" then offset else CFrame.identity), now)
	end
end

function Character.Step(self: Character, tool: BasePart?, now: number, camera: Vector3): ()
	local body, humanoid = self.Body, self.Humanoid
	if not body or not humanoid or not body.Parent then
		if self.Run then
			self.Run:SetEnabled(false, now)
		end
		if self.Water then
			self.Water:SetEnabled(false, now)
		end
		if self.Sweep then
			self.Sweep:Cancel(now)
		end
		self.SweepTrack = nil
		return
	end
	local near = (body.Position - camera).Magnitude <= Config.Distance
	local grounded = humanoid.Health > 0
		and AnimationConfig.GroundStates[humanoid:GetState()] == true
		and humanoid.FloorMaterial ~= Enum.Material.Air
	local available = grounded and near and humanoid.WalkSpeed > 0 and self.Model:IsDescendantOf(workspace)
	local speed = (body.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	local running = available
		and self.Model:GetAttribute(AnimationConfig.RunningAttribute) == true
		and speed > AnimationConfig.MovingThreshold
	-- The authored particle attachments sit three studs below the reference R15 root.
	local frame = body.CFrame * CFrame.new(0, Config.ReferenceRootHeight - humanoid.HipHeight - body.Size.Y / 2, 0)
	if running and not self.Run then
		self.Run = self:GetEffect("Run")
	end
	if self.Run then
		self.Run:SetEnabled(running, now)
		local offset = self.Run.Part:GetAttribute("SourceOffset")
		self.Run:Step(frame * (if typeof(offset) == "CFrame" then offset else CFrame.identity), now)
	end
	-- Watering intentionally locks WalkSpeed to zero; its server deadline authorizes the effect.
	self:UpdateWater(tool, now, grounded and near and self.Model:IsDescendantOf(workspace))
	self:UpdateSweep(frame, tool, now, available and speed <= AnimationConfig.MovingThreshold)
end

function Character.Destroy(self: Character): ()
	self.Janitor:Destroy()
end

return Character
