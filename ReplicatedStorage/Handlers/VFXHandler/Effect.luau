--!strict
-- One disposable authored emitter group. The handler's shared frame drives all delays and tails.
--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.VFX)
local Rules = require(ReplicatedStorage.Shared.VFXRules)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local Effect = {}
Effect.__index = Effect

type Emitter = { Object: ParticleEmitter, Delay: number, Count: number, Group: string, At: number? }
export type Effect = typeof(setmetatable(
	{} :: {
		Part: BasePart,
		Janitor: any,
		Emitters: { Emitter },
		Beams: { Beam },
		Tail: number,
		Enabled: boolean,
		StartedAt: number,
		ExpiresAt: number,
		Destroyed: boolean,
	},
	Effect
))

--[[ Private Functions ]]--
local function scaleSequence(sequence: NumberSequence, scale: number): NumberSequence
	local keys = {}
	for _, key in sequence.Keypoints do
		keys[#keys + 1] = NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale)
	end
	return NumberSequence.new(keys)
end

--[[ Handling ]]--
function Effect.new(template: BasePart, parent: Instance, scale: number?): Effect
	local part = template:Clone()
	local factor = scale or 1
	part.Size *= factor
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Transparency = 1
	local self: Effect = setmetatable({
		Part = part,
		Janitor = Janitor.new(),
		Emitters = {},
		Beams = {},
		Tail = 0,
		Enabled = false,
		StartedAt = 0,
		ExpiresAt = math.huge,
		Destroyed = false,
	}, Effect)
	self.Janitor:Add(part, "Destroy")
	for _, child in part:GetDescendants() do
		if child:IsA("Attachment") then
			child.Position *= factor
		end
		if child:IsA("Beam") then
			child.Enabled = false
			child.Width0 *= factor
			child.Width1 *= factor
			child.CurveSize0 *= factor
			child.CurveSize1 *= factor
			self.Beams[#self.Beams + 1] = child
		end
		if not child:IsA("ParticleEmitter") then
			continue
		end
		child.Enabled = false
		child.Rate = Rules.Number(child.Rate, 0, 0, Config.MaxEmitterRate)
		child.TimeScale = Rules.Number(child.TimeScale, 1, 0.1, 2)
		child.Size = scaleSequence(child.Size, factor)
		child.Speed = NumberRange.new(child.Speed.Min * factor, child.Speed.Max * factor)
		child.Acceleration *= factor
		local delay = Rules.Number(child:GetAttribute("EmitDelay"), 0, 0, Config.MaxDelay)
		local count =
			Rules.Number(child:GetAttribute("EmitCount"), math.max(1, math.round(child.Rate)), 1, Config.MaxEmitCount)
		local group = child.Parent
		self.Emitters[#self.Emitters + 1] = {
			Object = child,
			Delay = delay,
			Count = math.round(count),
			Group = if group then group.Name else "",
		}
		self.Tail = math.max(self.Tail, delay + math.min(child.Lifetime.Max, Config.MaxLifetime) / child.TimeScale)
	end
	part.Parent = parent
	return self
end

function Effect.SetEnabled(self: Effect, enabled: boolean, now: number): ()
	if self.Enabled == enabled then
		return
	end
	self.Enabled = enabled
	self.StartedAt = now
	for _, beam in self.Beams do
		beam.Enabled = enabled
	end
	if enabled then
		return
	end
	for _, entry in self.Emitters do
		entry.Object.Enabled = false
	end
end

function Effect.Burst(self: Effect, now: number, group: string?): ()
	for _, entry in self.Emitters do
		if not group or entry.Group == group then
			entry.At = now + entry.Delay
		end
	end
	self.ExpiresAt = now + self.Tail
end

function Effect.Cancel(self: Effect, now: number): ()
	self:SetEnabled(false, now)
	for _, entry in self.Emitters do
		entry.At = nil
	end
	self.ExpiresAt = now + self.Tail
end

function Effect.Step(self: Effect, frame: CFrame, now: number): ()
	if self.Destroyed then
		return
	end
	self.Part.CFrame = frame
	for _, entry in self.Emitters do
		entry.Object.Enabled = self.Enabled and now >= self.StartedAt + entry.Delay
		if entry.At and now >= entry.At then
			entry.At = nil
			entry.Object:Emit(entry.Count)
		end
	end
end

function Effect.Destroy(self: Effect): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Janitor:Destroy()
end

return Effect
