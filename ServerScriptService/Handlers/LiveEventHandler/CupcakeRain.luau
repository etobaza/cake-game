--!strict
-- Cupcake rain for one live event. The server drops cupcakes around every player and collects one
-- when its owner's character reaches it: there is no client request to trust, so the reward, the
-- per-event cap and the active cap are decided here alone. The models are placed at their landing
-- spot with a `LandsAt` time; clients animate the fall locally, and nothing is collectable before
-- it lands.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local Physics = require(script.Parent.Physics)
local Timeline = require(ReplicatedStorage.Shared.LiveEventTimeline)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "CupcakeRain" })

--[[ Constants ]]--
local STEP_SECONDS = 0.1
-- Extra vertical reach over PickupRadius: the root part floats above the floor the cupcake is on.
local PICKUP_HEIGHT_SLACK = 3
-- How far above the root part the landing ray starts, and how far down it looks for a floor.
local RAY_LIFT = 2
local RAY_DEPTH = 20
local FOLDER_NAME = "Cupcakes"

--[[ Types ]]--
type Drop = {
	Model: Model,
	OwnerId: number,
	Position: Vector3,
	LandsAt: number,
	ExpiresAt: number,
}

--[[ Tables ]]--
local CupcakeRain = {}
CupcakeRain.__index = CupcakeRain

--[[ Private Functions ]]--
local function findTemplate(): Model?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	node = node and node:FindFirstChild("Models")
	for _, name in Config.Rain.Model do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("Model") then node else nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A floor point in a ring around the root part, reachable in a straight line from it.
local function findLanding(root: BasePart, ignore: { Instance }): Vector3?
	local tuning = Config.Rain
	local params = Physics.ExcludeParams(ignore)

	local angle = math.random() * math.pi * 2
	local distance = tuning.MinRadius + math.random() * (tuning.MaxRadius - tuning.MinRadius)
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
	-- A wall between the player and the spot would make the cupcake unreachable.
	if workspace:Raycast(root.Position, offset, params) then
		return nil
	end
	local above = root.Position + offset + Vector3.new(0, RAY_LIFT, 0)
	local hit = workspace:Raycast(above, Vector3.new(0, -RAY_DEPTH, 0), params)
	return hit and hit.Position
end

--[[ Handling ]]--
function CupcakeRain.new(state: Timeline.State, parent: Instance): CupcakeRain
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = parent

	local self = setmetatable({
		State = state,
		Folder = folder,
		Template = findTemplate(),
		Drops = {} :: { Drop },
		-- Collected cupcakes per UserId, so rejoining does not reset the cap.
		Collected = {} :: { [number]: number },
		NextDropAt = {} :: { [number]: number },
		Loop = nil :: thread?,
	}, CupcakeRain)

	if not self.Template then
		Logger:Warn("Cupcake model not found; the rain is off for this event.")
		return self
	end
	self.Loop = task.spawn(function(): ()
		-- One failing step must not end the rain for the rest of the event. The same error repeats
		-- every step, so only a new message is logged.
		local lastError: string? = nil
		while true do
			local ok, result: unknown = pcall(self.Step, self, workspace:GetServerTimeNow())
			if not ok and tostring(result) ~= lastError then
				lastError = tostring(result)
				Logger:Warn(`Rain step failed, still running; check Configs/AdminAbuse.Rain and the model: {lastError}`)
			end
			task.wait(STEP_SECONDS)
		end
	end)
	return self
end

function CupcakeRain.Step(self: CupcakeRain, now: number): ()
	if not Timeline.IsLive(self.State, now) then
		return
	end
	self:Update(now)

	local tuning = Config.Rain
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		if now < (self.NextDropAt[userId] or 0) then
			continue
		end
		self.NextDropAt[userId] = now + tuning.Interval
		local active = self:CountActive(userId)
		if active < tuning.MaxActive and (self.Collected[userId] or 0) + active < tuning.MaxPerPlayer then
			self:Drop(player, now)
		end
	end
end

-- Collects landed cupcakes whose owner reached them and removes expired or orphaned ones.
function CupcakeRain.Update(self: CupcakeRain, now: number): ()
	local tuning = Config.Rain
	for index = #self.Drops, 1, -1 do
		local drop = self.Drops[index]
		local owner = Players:GetPlayerByUserId(drop.OwnerId)
		if now >= drop.ExpiresAt or not owner then
			drop.Model:Destroy()
			table.remove(self.Drops, index)
			continue
		end

		local root = rootOf(owner)
		if now < drop.LandsAt or not root then
			continue
		end
		local delta = root.Position - drop.Position
		local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
		if flat > tuning.PickupRadius or math.abs(delta.Y) > tuning.PickupRadius + PICKUP_HEIGHT_SLACK then
			continue
		end
		-- Coins need loaded cloud data. Until the profile attaches the cupcake stays where it is, so a
		-- pickup never pays nothing or uses up the per-event cap.
		if not DataHandler:GetData(owner) then
			continue
		end

		drop.Model:Destroy()
		table.remove(self.Drops, index)
		self:Collect(owner, drop.Position)
	end
end

function CupcakeRain.Collect(self: CupcakeRain, player: Player, position: Vector3): ()
	local userId = player.UserId
	self.Collected[userId] = (self.Collected[userId] or 0) + 1
	local before = EconomyHandler:GetCash(player)
	EconomyHandler:AddCash(player, Config.Rain.Coins, "Gameplay", Config.Rain.AnalyticsItem)
	local after = EconomyHandler:GetCash(player)
	local credited = math.round((after - before) * 100) / 100
	if credited > 0 then
		Bus.LiveEvent.CupcakeCollected:FireClient(player, position, credited, after)
	end
end

function CupcakeRain.CountActive(self: CupcakeRain, userId: number): number
	local count = 0
	for _, drop in self.Drops do
		if drop.OwnerId == userId then
			count += 1
		end
	end
	return count
end

function CupcakeRain.Drop(self: CupcakeRain, player: Player, now: number): ()
	local template = self.Template
	local root = rootOf(player)
	if not template or not root or not player.Character then
		return
	end
	local ignore: { Instance } = { self.Folder.Parent or self.Folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			ignore[#ignore + 1] = other.Character
		end
	end
	local landing = findLanding(root, ignore)
	if not landing then
		return
	end

	local tuning = Config.Rain
	local model = template:Clone()
	model:ScaleTo(tuning.ModelScale)
	Physics.MakeInert(model)
	local _, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(landing + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("LandsAt", now + tuning.FallSeconds)
	model.Parent = self.Folder

	self.Drops[#self.Drops + 1] = {
		Model = model,
		OwnerId = player.UserId,
		Position = landing,
		LandsAt = now + tuning.FallSeconds,
		ExpiresAt = now + tuning.FallSeconds + tuning.LifeSeconds,
	}
end

function CupcakeRain.Destroy(self: CupcakeRain): ()
	local loop = self.Loop
	self.Loop = nil
	if loop and coroutine.status(loop) ~= "running" then
		task.cancel(loop)
	end
	table.clear(self.Drops)
	self.Folder:Destroy()
end

export type CupcakeRain = typeof(setmetatable(
	{} :: {
		State: Timeline.State,
		Folder: Folder,
		Template: Model?,
		Drops: { Drop },
		Collected: { [number]: number },
		NextDropAt: { [number]: number },
		Loop: thread?,
	},
	CupcakeRain
))

return CupcakeRain
