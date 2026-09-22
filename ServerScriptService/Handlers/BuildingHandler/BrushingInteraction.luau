--!strict
-- The server owns the one-second action and its movement lock; clients pose the brush hand.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Base = require(ServerScriptService.Handlers.BaseHandler)
local Player = require(ServerScriptService.Handlers.PlayerHandler)
local Config = require(ReplicatedStorage.Shared.Configs.Garden)
local VFX = require(ReplicatedStorage.Shared.Configs.VFX)
local Bus = require(ReplicatedStorage.Shared.Bus)
local Janitor = require(ReplicatedStorage.Packages.janitor)

local BrushingInteraction = {}

function BrushingInteraction.Begin(building: any): boolean
	local player = building.Player
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not character
		or not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or humanoid.Sit
		or character:GetAttribute(Config.BrushStationAttribute)
		or character:GetAttribute(VFX.WaterStationAttribute)
		or Player.MovementLocks[player]
	then
		return false
	end
	local base = Base:GetBase(player)
	local floor = base and base:FindFirstChild("1ndFloor")
	local garden = floor and floor:FindFirstChild("Garden")
	local upgrades = garden and garden:FindFirstChild("Upgrades")
	local folder = upgrades and upgrades:FindFirstChild(Config.Sources[building.Id].Folder)
	local variant = folder and folder:FindFirstChild("Upgrade1")
	local body = variant and variant:FindFirstChildWhichIsA("MeshPart", true)
	if not body then
		return false
	end
	local point = body.CFrame:PointToObjectSpace(root.Position + Vector3.yAxis)
	local half = body.Size / 2
	point = body.CFrame:PointToWorldSpace(
		Vector3.new(
			math.clamp(point.X, -half.X, half.X),
			math.clamp(point.Y, -half.Y * 0.5, half.Y * 0.5),
			math.clamp(point.Z, -half.Z, half.Z)
		)
	)
	local facing = (point - root.Position) * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.001 then
		return false
	end
	if facing.Magnitude > Config.BrushReach then
		Bus.Progress.ActionFailed:FireClient(player, "too_far")
		return false
	end
	local target = CFrame.lookAt(point, point + facing.Unit)
	local key = `Brush:{building.Id}`
	local janitor = Janitor.new()
	building.Janitor:Add(janitor, "Destroy", "Brushing")
	janitor:Add(function(): ()
		character:SetAttribute(Config.BrushUntilAttribute, nil)
		character:SetAttribute(Config.BrushTargetAttribute, nil)
		character:SetAttribute(Config.BrushStationAttribute, nil)
		Player:SetMovementLocked(player, key, false)
	end, true)
	janitor:Add(
		player.CharacterRemoving:Connect(function(): ()
			building.State.CareUntil = 0
			building.Part:SetAttribute("GardenCareUntil", nil)
			building.Part:SetAttribute("GardenCareAction", nil)
			BrushingInteraction.End(building)
		end),
		"Disconnect"
	)
	Player:SetMovementLocked(player, key, true)
	character:SetAttribute(Config.BrushStationAttribute, building.Id)
	character:SetAttribute(Config.BrushTargetAttribute, target)
	character:SetAttribute(Config.BrushUntilAttribute, workspace:GetServerTimeNow() + Config.BrushSeconds)
	Bus.VFX.Burst:Fire("Cleaning", building.Part, target, player.UserId, workspace:GetServerTimeNow())
	return true
end

function BrushingInteraction.CanContinue(building: any): boolean
	local character = building.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = character and character:GetAttribute(Config.BrushTargetAttribute)
	return root ~= nil
		and root:IsA("BasePart")
		and typeof(target) == "CFrame"
		and character:GetAttribute(Config.BrushStationAttribute) == building.Id
		and (root.Position + Vector3.yAxis - target.Position).Magnitude <= Config.BrushReach + 0.5
end

function BrushingInteraction.End(building: any): ()
	building.Janitor:Remove("Brushing")
end

return BrushingInteraction
