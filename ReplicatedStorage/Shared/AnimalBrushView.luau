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
		Hand = nil,
	}, AnimalBrushView) :: any
end

function AnimalBrushView.Clear(self: AnimalBrushView): ()
	self.Janitor:Cleanup()
	self.Brush, self.Hand = nil, nil
end

function AnimalBrushView.Bind(self: AnimalBrushView): boolean
	local character = self.Character
	local hand = character:FindFirstChild("RightHand")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local assets = ReplicatedStorage.Assets.Models:FindFirstChild("GardenCare")
	local source = assets and assets:FindFirstChild("AnimalBrush")
	if not hand or not hand:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or not source then
		return false
	end
	local brush = FoodModel.FromSource(source, self.Parent, Config.BrushSize)
	if not brush then
		return false
	end
	brush.Model.Name = "AnimalBrush"
	brush.Model.Parent = nil
	self.Janitor:Add(brush, "Destroy")

	self.Brush, self.Hand = brush, hand
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

	if not self.Brush then
		self:Bind()
	end
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
		Hand: BasePart?,
	},
	AnimalBrushView
))

return AnimalBrushView
