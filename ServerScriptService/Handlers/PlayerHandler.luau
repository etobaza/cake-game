--!strict
-- Character movement: walking, running, spill slowdown and keyed server locks while a mixer runs.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local AnimationConfig = require(_Configs.CharacterAnimations)
local DayCycleConfig = require(_Configs.DayCycle)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Tables ]]--
local PlayerHandler = {
	dependencies = { "UpgradeHandler" },
	priority = 50,
}

type MovementDefaults = {
	Humanoid: Humanoid,
	JumpPower: number,
	JumpHeight: number,
	AutoRotate: boolean,
}

--[[ Private Functions ]]--
local function GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function HasMovementLock(self: PlayerHandler, player: Player): boolean
	local locks = self.MovementLocks[player]
	return locks ~= nil and next(locks) ~= nil
end

--[[ Handling ]]--
function PlayerHandler.OnInit(self: PlayerHandler): ()
	self.Slowed = {}
	self.Running = {}
	self.MovementLocks = {}
	self.MovementDefaults = {}
end

function PlayerHandler.OnStart(self: PlayerHandler): ()
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:ApplySpeed(player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild("Humanoid")
			self:ApplySpeed(player)
		end)
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild("Humanoid")
			self:ApplySpeed(player)
		end)

		self:ApplySpeed(player)
	end

	UpgradeHandler.StatsChanged:Connect(function(player: Player)
		self:ApplySpeed(player)
	end)

	Bus.Player.SetRunning.OnServerEvent:Connect(function(player: Player, isRunning: any)
		if typeof(isRunning) ~= "boolean" then
			return
		end

		self:SetRunning(player, isRunning)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.Slowed[player] = nil
		self.Running[player] = nil
		self.MovementLocks[player] = nil
		self.MovementDefaults[player] = nil
	end)
end

-- The only place where WalkSpeed is set: otherwise the slowdown and the upgrades would fight.
function PlayerHandler.ApplySpeed(self: PlayerHandler, player: Player): ()
	local humanoid = GetHumanoid(player)
	if not humanoid then
		return
	end

	-- Animator must originate on the server for owner-started tracks to replicate to other players.
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local character = humanoid.Parent
	if character then
		character:SetAttribute(
			AnimationConfig.RunningAttribute,
			self.Running[player] == true and not HasMovementLock(self, player)
		)
	end

	if HasMovementLock(self, player) then
		local defaults = self.MovementDefaults[player]
		if not defaults or defaults.Humanoid ~= humanoid then
			self.MovementDefaults[player] = {
				Humanoid = humanoid,
				JumpPower = humanoid.JumpPower,
				JumpHeight = humanoid.JumpHeight,
				AutoRotate = humanoid.AutoRotate,
			}
		end

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		humanoid.Jump = false
		humanoid:Move(Vector3.zero)

		local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			root.AssemblyAngularVelocity = Vector3.zero
		end
		return
	end

	local defaults = self.MovementDefaults[player]
	if defaults and defaults.Humanoid == humanoid then
		humanoid.JumpPower = defaults.JumpPower
		humanoid.JumpHeight = defaults.JumpHeight
		humanoid.AutoRotate = defaults.AutoRotate
	end
	self.MovementDefaults[player] = nil

	local speed = UpgradeHandler:GetStat(player, if self.Running[player] then "RunSpeed" else "WalkSpeed")

	if self.Slowed[player] then
		speed *= DayCycleConfig.SpillSlowFactor
	end

	humanoid.WalkSpeed = speed
end

-- Locks are keyed so two mixers (or a future second system) cannot unlock each other early.
function PlayerHandler.SetMovementLocked(self: PlayerHandler, player: Player, key: string, isLocked: boolean): ()
	local locks = self.MovementLocks[player]
	if isLocked then
		if not locks then
			locks = {}
			self.MovementLocks[player] = locks
		end
		if locks[key] then
			return
		end
		locks[key] = true
		self.Running[player] = nil
	elseif locks then
		if not locks[key] then
			return
		end
		locks[key] = nil
		if next(locks) == nil then
			self.MovementLocks[player] = nil
		end
	else
		return
	end

	self:ApplySpeed(player)
end

-- The client turns running on with its own key, but the server sets the speed.
function PlayerHandler.SetRunning(self: PlayerHandler, player: Player, isRunning: boolean): ()
	if self.Running[player] == isRunning then
		return
	end

	if isRunning then
		self.Running[player] = true
	else
		self.Running[player] = nil
	end
	self:ApplySpeed(player)
end

-- Called when the player enters and leaves a spill.
function PlayerHandler.SetSlowed(self: PlayerHandler, player: Player, isSlowed: boolean): ()
	if self.Slowed[player] == isSlowed then
		return
	end

	if isSlowed then
		self.Slowed[player] = true
	else
		self.Slowed[player] = nil
	end
	self:ApplySpeed(player)
end

export type PlayerHandler = typeof(PlayerHandler) & {
	Slowed: { [Player]: boolean },
	Running: { [Player]: boolean },
	MovementLocks: { [Player]: { [string]: boolean } },
	MovementDefaults: { [Player]: MovementDefaults },
}

return PlayerHandler :: PlayerHandler
