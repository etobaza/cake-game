--!strict
-- Animal care and its produced food are separate targets, sharing one authoritative garden node.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Garden)
local View = require(script.Parent.View)

local AnimalPrompts = {}

function AnimalPrompts.Attach(building: any, template: Instance, transform: CFrame): ()
	local source = Config.Sources[building.Id]
	if not source or source.Care ~= "Animal" then
		return
	end
	local anchors = template:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(building.Id)
	local point = anchor and anchor:FindFirstChild("GardenProduce1")
	if not point or not point:IsA("Attachment") then
		return
	end
	building.Part:SetAttribute(Config.AnimalActionAttribute, "Brush")
	local prompt = building.Part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.MaxActivationDistance = Config.BrushPromptDistance
	end
	local output = Instance.new("Part")
	output.Name = "AnimalProduce"
	output.Size = Vector3.one
	output.Transparency = 1
	output.Anchored = true
	output.CanCollide, output.CanTouch, output.CanQuery = false, false, false
	output.CFrame = transform * point.WorldCFrame + Vector3.yAxis
	output:SetAttribute(Config.AnimalActionAttribute, "Harvest")
	output.Parent = building.Part
	View.Dress(output, building.Id, building.Kind, building.Definition, building.Player.UserId)
	local harvestPrompt = output:FindFirstChildOfClass("ProximityPrompt")
	if harvestPrompt then
		harvestPrompt.MaxActivationDistance = Config.BrushPromptDistance
	end
	building.Janitor:Add(output, "Destroy", "AnimalProducePrompt")
end

return AnimalPrompts
