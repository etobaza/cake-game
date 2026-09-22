--!strict
-- TrayHandler owns one view per character. Server attributes authorize a temporary empty-hand tool.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Garden)
local FoodModel = require(ReplicatedStorage.Shared.FoodModel)
local Janitor = require(ReplicatedStorage.Packages.janitor)

local AnimalBrushView = {}
AnimalBrushView.__index = AnimalBrushView

function AnimalBrushView.new(character: Model, parent: Instance): AnimalBrushView
	return setmetatable({
		Character = character,
		Parent = parent,
		Janitor = Janitor.new(),
		Brush = nil,
		IK = nil,
		Target = nil,
		Hand = nil,
		Root = nil,
	}, AnimalBrushView) :: any
end

function AnimalBrushView.Clear(self: AnimalBrushView): ()
	if self.IK then
		self.IK.Enabled = false
	end
	self.Janitor:Cleanup()
	self.Brush, self.IK, self.Target, self.Hand, self.Root = nil, nil, nil, nil, nil
end

function AnimalBrushView.Bind(self: AnimalBrushView): boolean
	local character = self.Character
	local hand = character:FindFirstChild("RightHand")
	local arm = character:FindFirstChild("RightUpperArm")
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local assets = ReplicatedStorage.Assets.Models:FindFirstChild("GardenCare")
	local source = assets and assets:FindFirstChild("AnimalBrush")
	if
		not hand
		or not hand:IsA("BasePart")
		or not arm
		or not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or not source
	then
		return false
	end
	local brush = FoodModel.FromSource(source, self.Parent, Config.BrushSize)
	if not brush then
		return false
	end
	brush.Model.Name = "AnimalBrush"
	brush.Model.Parent = nil
	self.Janitor:Add(brush, "Destroy")
	local target = Instance.new("Attachment")
	target.Name = "AnimalBrushTarget"
	target.Parent = root
	self.Janitor:Add(target, "Destroy")
	local ik = Instance.new("IKControl")
	ik.Name = "AnimalBrushing"
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = arm
	ik.EndEffector = hand
	ik.Target = target
	ik.SmoothTime = 0.04
	ik.Weight = 0
	ik.Parent = humanoid
	self.Janitor:Add(ik, "Destroy")
	self.Brush, self.IK, self.Target, self.Hand, self.Root = brush, ik, target, hand, root
	return true
end

function AnimalBrushView.Step(self: AnimalBrushView, now: number): ()
	local untilTime = self.Character:GetAttribute(Config.BrushUntilAttribute)
	local frame = self.Character:GetAttribute(Config.BrushTargetAttribute)
	local humanoid = self.Character:FindFirstChildOfClass("Humanoid")
	if
		typeof(untilTime) ~= "number"
		or untilTime <= now
		or typeof(frame) ~= "CFrame"
		or not humanoid
		or humanoid.Health <= 0
		or humanoid.Sit
	then
		if self.Brush then
			self:Clear()
		end
		return
	end
	if not self.Brush and not self:Bind() then
		return
	end
	local elapsed = math.clamp(Config.BrushSeconds - (untilTime - now), 0, Config.BrushSeconds)
	local weight = math.clamp(math.min(elapsed, untilTime - now) / Config.BrushBlendSeconds, 0, 1)
	local stroke = math.sin(elapsed / Config.BrushSeconds * math.pi * 2 * Config.BrushCycles) * Config.BrushStroke
	local target = self.Target :: Attachment
	target.WorldCFrame = frame * CFrame.new(stroke, 0, -0.3)
	local ik = self.IK :: IKControl
	ik.Weight = weight
end

function AnimalBrushView.Align(self: AnimalBrushView): ()
	local brush, hand = self.Brush, self.Hand
	if not brush or not hand then
		return
	end
	brush:SetCFrame(hand.CFrame * Config.BrushGrip)
	brush.Model.Parent = self.Parent
end

function AnimalBrushView.Destroy(self: AnimalBrushView): ()
	self:Clear()
	self.Janitor:Destroy()
end

export type AnimalBrushView = typeof(setmetatable(
	{} :: {
		Character: Model,
		Parent: Instance,
		Janitor: any,
		Brush: FoodModel.FoodModel?,
		IK: IKControl?,
		Target: Attachment?,
		Hand: BasePart?,
		Root: BasePart?,
	},
	AnimalBrushView
))

return AnimalBrushView
