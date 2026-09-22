--!strict
-- Owns an accepted watering action and its movement lock; the client turns in place.
-- GardenNode's existing care deadline/tick decides completion and cancellation.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Base = require(ServerScriptService.Handlers.BaseHandler)
local Player = require(ServerScriptService.Handlers.PlayerHandler)
local Config = require(ReplicatedStorage.Shared.Configs.Garden)
local VFX = require(ReplicatedStorage.Shared.Configs.VFX)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local WateringInteraction = {}

--[[ Handling ]]--
function WateringInteraction.Begin(building: any): boolean
	local player = building.Player
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
		or not humanoid
		or not root
		or not root:IsA("BasePart")
		or humanoid.Health <= 0
		or humanoid.Sit
		or character:GetAttribute(VFX.WaterStationAttribute)
		or character:GetAttribute(Config.BrushStationAttribute)
	then
		return false
	end
	local anchor, transform = Base:GetAnchor(building.Id), Base:GetTransform(player)
	if not anchor or not transform then
		return false
	end
	local floor = transform * anchor
	local target = floor:PointToWorldSpace(Config.WaterTargetOffsets[building.Id] or Vector3.zero)
		+ Vector3.yAxis * Config.WaterTargetHeight
	if ((target - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 0.001 then
		return false
	end

	local key = `Water:{building.Id}`
	local janitor = Janitor.new()
	building.Janitor:Add(janitor, "Destroy", "Watering")
	janitor:Add(function(): ()
		character:SetAttribute(VFX.WaterUntilAttribute, nil)
		character:SetAttribute(VFX.WaterStationAttribute, nil)
		character:SetAttribute(VFX.WaterTargetAttribute, nil)
		Player:SetMovementLocked(player, key, false)
	end, true)
	janitor:Add(
		player.CharacterRemoving:Connect(function(): ()
			building.State.CareUntil = 0
			building.Part:SetAttribute("GardenCareUntil", nil)
			building.Part:SetAttribute("GardenCareAction", nil)
			WateringInteraction.End(building)
		end),
		"Disconnect"
	)
	Player:SetMovementLocked(player, key, true)
	character:SetAttribute(VFX.WaterStationAttribute, building.Id)
	character:SetAttribute(VFX.WaterTargetAttribute, target)
	return true
end

function WateringInteraction.End(building: any): ()
	building.Janitor:Remove("Watering")
end

return WateringInteraction
