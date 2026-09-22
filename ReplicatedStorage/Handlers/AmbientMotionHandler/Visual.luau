--!strict
-- One local visual copy. Its stationary source continues to own collisions and server visibility.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Config = require(ReplicatedStorage.Shared.Configs.AmbientMotion)
local Clip = require(script.Parent.Clip)

local Visual = {}
Visual.__index = Visual
export type Visual = typeof(setmetatable(
	{} :: {
		Source: BasePart,
		Parent: Instance,
		Kind: string,
		Home: CFrame,
		Center: Vector3,
		Phase: number,
		Speed: number,
		Clip: Clip.Clip?,
		Clone: BasePart?,
		Bones: { Bone },
		Janitor: any,
		Hidden: number,
	},
	Visual
))

function Visual.new(source: BasePart, parent: Instance, kind: string, clip: Clip.Clip?): Visual
	local home = source.CFrame
	local center = source:GetAttribute(Config.CenterAttribute)
	local sharedPhase = kind == "Plant" or kind == "Cow" or kind == "Chicken"
	local phasePosition = if sharedPhase and typeof(center) == "Vector3" then center else home.Position
	local phase = (phasePosition.X * 0.37 + phasePosition.Z * 0.19 + phasePosition.Y * 1.7) % (math.pi * 2)
	return setmetatable({
		Source = source,
		Parent = parent,
		Kind = kind,
		Home = home,
		Center = if typeof(center) == "Vector3"
			then center
			elseif kind == "Plant" then home.Position - Vector3.yAxis * source.Size.Y / 2
			else home.Position,
		Phase = phase,
		Speed = 0.85 + (math.sin(phase) + 1) * 0.15,
		Clip = clip,
		Clone = nil,
		Bones = {},
		Janitor = Janitor.new(),
		Hidden = source.LocalTransparencyModifier,
	}, Visual)
end

function Visual.Show(self: Visual): ()
	if self.Clone then
		return
	end
	local clone = self.Source:Clone()
	clone:RemoveTag(Config.Tag)
	clone.Name = self.Kind
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanQuery = false
	clone.CanTouch = false
	clone.LocalTransparencyModifier = self.Hidden
	clone.CFrame = self.Home
	for _, child in clone:GetDescendants() do
		if child:IsA("Bone") and self.Clip and self.Clip.Tracks[child.Name] then
			self.Bones[#self.Bones + 1] = child
		end
	end
	clone.Parent = self.Parent
	self.Clone = clone
	self.Janitor:Add(clone, "Destroy")
	self.Source.LocalTransparencyModifier = 1
	self.Janitor:Add(function(): ()
		if self.Source.Parent then
			self.Source.LocalTransparencyModifier = self.Hidden
		end
	end, true)
end

function Visual.Hide(self: Visual): ()
	if not self.Clone then
		return
	end
	self.Janitor:Cleanup()
	self.Clone = nil
	table.clear(self.Bones)
end

function Visual.Step(self: Visual, now: number, cameraPosition: Vector3): ()
	if
		not self.Source:IsDescendantOf(workspace)
		or self.Source.Transparency >= 1
		or (self.Home.Position - cameraPosition).Magnitude > Config.MaxDistance
	then
		self:Hide()
		return
	end
	self:Show()
	local clone = self.Clone :: BasePart
	clone.Transparency = self.Source.Transparency
	local time = now * self.Speed + self.Phase
	if self.Kind == "Bee" then
		local angle = time * Config.BeeOrbitSpeed
		local rotation = CFrame.Angles(0, angle, 0)
		local offset = self.Home.Position - self.Center
		local position = self.Center
			+ rotation:VectorToWorldSpace(offset)
			+ Vector3.yAxis * (math.sin(time * 2) * Config.BeeBob)
		clone.CFrame = CFrame.new(position)
			* rotation
			* self.Home.Rotation
			* CFrame.Angles(0, 0, math.sin(time * 1.4) * Config.BeeBank)
	elseif self.Kind == "Plant" then
		local sway = math.sin(time * Config.PlantSpeed) * Config.PlantAngle
		clone.CFrame = CFrame.new(self.Center)
			* CFrame.Angles(sway * 0.4, 0, sway)
			* CFrame.new(-self.Center)
			* self.Home
	end
	local clip = self.Clip
	if clip then
		local speeds = Config.ClipSpeeds :: { [string]: number }
		local phase = (time * (speeds[self.Kind] or 1)) % clip.Duration
		for _, bone in self.Bones do
			bone.Transform = Clip.Sample(clip.Tracks[bone.Name], phase)
		end
	end
end

function Visual.Destroy(self: Visual): ()
	self:Hide()
	self.Janitor:Destroy()
end
return Visual
