--!strict
-- One visual frame callback for all streamed garden models, with shared baked clips.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Config = require(ReplicatedStorage.Shared.Configs.AmbientMotion)
local Clip = require(script.Clip)
local Visual = require(script.Visual)

local AmbientMotionHandler = {}

function AmbientMotionHandler.OnInit(self: AmbientMotionHandler): ()
	self.Janitor = Janitor.new()
	self.Models = {}
	self.Clips = {}
end

function AmbientMotionHandler.OnStart(self: AmbientMotionHandler): ()
	local animations = ReplicatedStorage.Assets:WaitForChild("Animations", 10)
	local folder = animations and animations:WaitForChild("Ambient", 10)
	if folder then
		for _, sequence in folder:GetChildren() do
			if sequence:IsA("KeyframeSequence") then
				local clip = Clip.Read(sequence)
				if clip then
					self.Clips[sequence.Name] = clip
				end
			end
		end
	else
		print("[AmbientMotionHandler] Assets.Animations.Ambient is missing")
	end
	local root = Instance.new("Folder")
	root.Name = "AmbientVisuals"
	root.Parent = workspace
	self.Root = root
	self.Janitor:Add(root, "Destroy")
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(function(instance: Instance): ()
			self:Track(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(instance: Instance): ()
			self:Untrack(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Config.Tag) do
		self:Track(instance)
	end
	self.Janitor:Add(
		RunService.PreSimulation:Connect(function(): ()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local now = workspace:GetServerTimeNow()
			for _, visual in self.Models do
				visual:Step(now, camera.CFrame.Position)
			end
		end),
		"Disconnect"
	)
end

function AmbientMotionHandler.Track(self: AmbientMotionHandler, instance: Instance): ()
	if not instance:IsA("BasePart") or self.Models[instance] then
		return
	end
	local kind = instance:GetAttribute(Config.KindAttribute)
	if typeof(kind) ~= "string" then
		return
	end
	local visual = Visual.new(instance, self.Root, kind, self.Clips[kind])
	self.Models[instance] = visual
	self.Janitor:Add(visual, "Destroy", instance)
end

function AmbientMotionHandler.Untrack(self: AmbientMotionHandler, instance: Instance): ()
	self.Janitor:Remove(instance)
	self.Models[instance] = nil
end

function AmbientMotionHandler.Destroy(self: AmbientMotionHandler): ()
	self.Janitor:Destroy()
	table.clear(self.Models)
end

-- Interaction visuals follow the animated copy while its stationary collision source is hidden.
function AmbientMotionHandler.GetVisiblePart(self: AmbientMotionHandler, source: BasePart): BasePart
	local visual = self.Models[source]
	return if visual and visual.Clone and visual.Clone.Parent then visual.Clone else source
end

export type AmbientMotionHandler = typeof(AmbientMotionHandler) & {
	Janitor: any,
	Root: Folder,
	Models: { [Instance]: Visual.Visual },
	Clips: { [string]: Clip.Clip },
}
return AmbientMotionHandler :: AmbientMotionHandler
