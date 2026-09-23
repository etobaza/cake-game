--!strict
-- The server owns the one-second action and its movement lock; clients pose the brush hand.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Base = require(ServerScriptService.Handlers.BaseHandler)
local Player = require(ServerScriptService.Handlers.PlayerHandler)
local Config = require(ReplicatedStorage.Shared.Configs.Garden)
local Motion = require(ReplicatedStorage.Shared.Configs.AmbientMotion)
local VFX = require(ReplicatedStorage.Shared.Configs.VFX)
local Bus = require(ReplicatedStorage.Shared.Bus)
local Janitor = require(ReplicatedStorage.Packages.janitor)

local BrushingInteraction = {}

-- A flock shares one production node, but care must reach the bird beside the player.
local function nearestBodyPoint(variant: Instance?, position: Vector3): Vector3?
	if not variant then
		return nil
	end
	local nearest: Vector3? = nil
	local distance = math.huge
	for _, body in variant:GetDescendants() do
		if not body:IsA("MeshPart") then
			continue
		end
		local kind = Motion.MeshKinds[body.MeshId:match("%d+") or ""]
		if kind ~= "Chicken" and kind ~= "Cow" then
			continue
		end
		local localPoint = body.CFrame:PointToObjectSpace(position + Vector3.yAxis)
		local half = body.Size / 2
		local point = body.CFrame:PointToWorldSpace(Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y * 0.5, half.Y * 0.5),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		))
		local gap = ((point - position) * Vector3.new(1, 0, 1)).Magnitude
		if gap < distance then
			nearest, distance = point, gap
		end
	end
	return nearest
end

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
	local variant = folder and folder:FindFirstChild(Config.Sources[building.Id].DryVariant or "Upgrade1")
	local point = nearestBodyPoint(variant, root.Position)
	if not point then
		return false
	end
	local facing = (point - root.Position) * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.001 then
		facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
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
		-- Use the same horizontal reach as Begin; short birds must not cancel a valid action.
		and ((root.Position - target.Position) * Vector3.new(1, 0, 1)).Magnitude <= Config.BrushReach + 0.5
end

function BrushingInteraction.End(building: any): ()
	building.Janitor:Remove("Brushing")
end

return BrushingInteraction
