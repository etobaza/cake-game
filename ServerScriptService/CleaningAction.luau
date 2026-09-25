--!strict
-- Accepted cleaning owns a short character lock; the target's lifetime owns its cleanup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Configs.CharacterAnimations)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local PlayerHandler = require(ServerScriptService.Handlers.PlayerHandler)
local SweepPlacement = require(ServerScriptService.SweepPlacement)

local CleaningAction = {}
local LOCK_KEY = "CleaningAction"

function CleaningAction.Begin(player: Player, target: BasePart, action: string, owner: Janitor.Janitor): (() -> ())?
	local definition = Config.Actions[action]
	local seconds = definition and definition.LockSeconds
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not seconds
		or not character
		or not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or humanoid.Sit
		or not Config.GroundStates[humanoid:GetState()]
		or root.Anchored
		or not target:IsDescendantOf(workspace)
		or PlayerHandler.MovementLocks[player]
	then
		return nil
	end

	local goal: CFrame? = nil
	if action == "Sweep" then
		goal = SweepPlacement.Resolve(character, root, humanoid, target)
		if not goal then
			return nil
		end
	end

	local janitor = Janitor.new()
	owner:Add(janitor, "Destroy", LOCK_KEY)
	local function finish(): ()
		owner:Remove(LOCK_KEY)
	end
	janitor:Add(function(): ()
		root.Anchored = false
		PlayerHandler:SetMovementLocked(player, LOCK_KEY, false)
	end, true)
	janitor:Add(player.CharacterRemoving:Connect(finish), "Disconnect")
	janitor:Add(humanoid.Died:Connect(finish), "Disconnect")
	janitor:Add(target.Destroying:Connect(finish), "Disconnect")

	PlayerHandler:SetMovementLocked(player, LOCK_KEY, true)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	local position = root.Position
	local facing = (target.Position - position) * Vector3.new(1, 0, 1)
	if goal then
		root.CFrame = goal
	elseif facing.Magnitude > 0.001 then
		root.CFrame = CFrame.lookAt(position, position + facing)
	end
	-- Both authored cleaning clips last one second. Include their final blend back to idle.
	janitor:Add(task.delay(seconds + Config.FadeTime, finish), true)
	return finish
end

return CleaningAction
