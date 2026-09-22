-- Spills: dough dropped while cooking and mopped by hand with the broom.
--
-- The puddles are the artist's own models, standing in the kitchen's `Spills` folder. Nothing is
-- spawned and nothing is destroyed: a spill is one of those models made visible and given a prompt,
-- and mopping it hides it again. Every spill is caused by kitchen work; the first batch guarantees
-- the tutorial spill and later batches roll the configured chance.

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)
local TutorialEvents = require(ServerScriptService.TutorialEvents)
local BaseConfig = require(_Configs.Base)
local BaseHandler = require(_Handlers.BaseHandler)
local BuildingHandler = require(_Handlers.BuildingHandler)
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataHandler = require(_Handlers.DataHandler)
local DayCycleConfig = require(_Configs.DayCycle)
local GameTypes = require(_Shared.GameTypes)
local InventoryHandler = require(_Handlers.InventoryHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local PlayerHandler = require(_Handlers.PlayerHandler)
local Sanitize = require(_Shared.Sanitize)
local TickHandler = require(_Handlers.TickHandler)
local View = require(_Handlers.BuildingHandler.View)

--[[ Constants ]]--
local FOLDER_NAME = "Spills"
local KIND_NAME = "Spill"
local CLEAN_DISTANCE = 12
local TOOL: GameTypes.ItemKind = "Tool"

--[[ Tables ]]--
local CleaningHandler = {
	dependencies = {
		"DataHandler",
		"TickHandler",
		"BaseHandler",
		"PlayerHandler",
		"CollisionHandler",
		"InventoryHandler",
		"BuildingHandler",
	},
	priority = 40,
}

type Runtime = {
	Janitor: any,
	-- The artist's puddle model behind each live spill id.
	Parts: { [string]: BasePart },
	Homes: { [BasePart]: CFrame },
}

--[[ Private Functions ]]--
local function GetSpills(player: Player): { [string]: boolean }?
	local data = DataHandler:GetData(player)
	return data and data.Session.Spills
end

local function GetKitchen(player: Player): Instance?
	local model = BaseHandler:GetBase(player)
	local floor = model and model:FindFirstChild("1ndFloor")

	return floor and floor:FindFirstChild("Kitchen")
end

local function CountSpills(spills: { [string]: boolean }): number
	local count = 0
	for _ in spills do
		count += 1
	end

	return count
end

-- The artist's puddles, in the order they are drawn. Spill N is model N.
local function GetSpillParts(player: Player): { BasePart }
	local kitchen = GetKitchen(player)
	local folder = kitchen and kitchen:FindFirstChild(FOLDER_NAME)
	if not folder then
		return {}
	end

	local parts: { BasePart } = {}
	for _, child in folder:GetChildren() do
		local part = if child:IsA("BasePart") then child else child:FindFirstChildWhichIsA("BasePart", true)
		if part then
			table.insert(parts, part)
		end
	end

	return parts
end

local function GetKitchenFloor(player: Player): BasePart?
	local kitchen = GetKitchen(player)
	local ground = kitchen and kitchen:FindFirstChild("Up/Ground")
	local best: BasePart? = nil
	local bestArea = 0

	for _, child in (ground and ground:GetDescendants() or {}) do
		if child:IsA("BasePart") then
			local area = child.Size.X * child.Size.Z
			if area > bestArea then
				best = child
				bestArea = area
			end
		end
	end

	return best
end

-- A puddle is on the floor or it is not; the authored model moves but is never destroyed.
-- The tag goes with the look: the client enables a prop's prompt from it (InteractHandler), so a
-- puddle that only turned invisible would still offer "Sweep" over an empty floor.
local function SetSpillShown(part: BasePart, shown: boolean): ()
	part.Transparency = if shown then 0 else 1
	part.CanQuery = shown
	part.CanTouch = shown

	if shown then
		CollectionService:AddTag(part, BuildingsConfig.Tag)
	else
		CollectionService:RemoveTag(part, BuildingsConfig.Tag)
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = shown
	end
end

-- Moves a prop together with its furniture: the model pieces are anchored one by one, so they all
-- take the same delta as the block they hang on.
local function MoveProp(part: BasePart, goal: CFrame): ()
	local delta = goal * part.CFrame:Inverse()

	part.CFrame = goal

	for _, piece in part:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.CFrame = delta * piece.CFrame
		end
	end
end

local function FarFromOtherSpills(runtime: Runtime, part: BasePart, position: Vector3): boolean
	for _, other in runtime.Parts do
		if other ~= part then
			local delta = Vector3.new(position.X - other.Position.X, 0, position.Z - other.Position.Z)
			if delta.Magnitude < DayCycleConfig.SpillSeparation then
				return false
			end
		end
	end

	return true
end

local function IsOpenFloor(player: Player, part: BasePart, floor: BasePart, goal: CFrame): boolean
	local kitchen = GetKitchen(player)
	local spillsFolder = kitchen and kitchen:FindFirstChild(FOLDER_NAME)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { floor, spillsFolder or part }

	local boxSize = Vector3.new(math.max(part.Size.X - 0.5, 1), 2.5, math.max(part.Size.Z - 0.5, 1))
	for _, obstacle in workspace:GetPartBoundsInBox(goal * CFrame.new(0, 1, 0), boxSize, overlap) do
		if obstacle.CanCollide then
			return false
		end
	end

	return true
end

local function RandomSpillCFrame(player: Player, runtime: Runtime, part: BasePart): CFrame?
	local floor = GetKitchenFloor(player)
	if not floor then
		return nil
	end

	local margin = math.max(part.Size.X, part.Size.Z) / 2 + 1
	local halfX = floor.Size.X / 2 - margin
	local halfZ = floor.Size.Z / 2 - margin
	if halfX <= 0 or halfZ <= 0 then
		return nil
	end

	for _ = 1, DayCycleConfig.SpillPlacementAttempts do
		local localX = (math.random() * 2 - 1) * halfX
		local localZ = (math.random() * 2 - 1) * halfZ
		local position = (floor.CFrame * CFrame.new(localX, floor.Size.Y / 2 + part.Size.Y / 2 + 0.01, localZ)).Position
		local goal = CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
		if FarFromOtherSpills(runtime, part, position) and IsOpenFloor(player, part, floor, goal) then
			return goal
		end
	end

	return nil
end

--[[ Handling ]]--
function CleaningHandler.OnInit(self: CleaningHandler): ()
	self.Runtime = {}
end

function CleaningHandler.OnStart(self: CleaningHandler): ()
	-- Closing time does not tidy up: dough left on the floor is still there in the morning.

	TickHandler.Tick:Connect(function()
		self:UpdateSpills()
	end)

	Bus.Cafe.CleanSpill.OnServerEvent:Connect(function(player: Player, spillId: any)
		local id = Sanitize.Id(spillId)
		if id then
			self:Clean(player, id)
		end
	end)

	-- A claimed bakery starts clean. The first kitchen action supplies the broom lesson.
	BaseHandler.BaseReady:Connect(function(player: Player)
		self:StartFloor(player)
	end)

	-- Dough hits the floor while a station is working, not on a clock.
	BuildingHandler.StateChanged:Connect(function(player: Player, building: any, newState: string)
		local mixedBatchReady = building.Definition.Mixes and newState == "Ready"
		if building.Definition.StateField == "Stations" and (mixedBatchReady or newState == "Cooking") then
			self:OnStationWorking(player)
		end
	end)

	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:ReleaseFloor(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:ReleaseFloor(player)
	end)

	-- The base may have been claimed before this handler subscribed.
	for _, player in Players:GetPlayers() do
		if BaseHandler:GetBase(player) then
			self:StartFloor(player)
		end
	end
end

-- Hides every puddle. Runs once per claimed bakery; cooking is the only thing that dirties it.
function CleaningHandler.StartFloor(self: CleaningHandler, player: Player): ()
	local runtime = self.Runtime[player]
	if not runtime then
		runtime = {
			Janitor = Janitor.new(),
			Parts = {},
			Homes = {},
		}
		self.Runtime[player] = runtime
	end

	self:PrepareSpills(player)
	self:ClearSpills(player)
end

-- BaseRemoving observers may run after BaseHandler has forgotten the claim. Cleanup uses
-- the cached authored parts, never a fresh lookup through the departing player's base.
function CleaningHandler.ReleaseFloor(self: CleaningHandler, player: Player): ()
	local runtime = self.Runtime[player]
	if not runtime then
		return
	end
	self:ClearSpills(player)
	runtime.Janitor:Destroy()
	self.Runtime[player] = nil
end

function CleaningHandler.ClearSpills(self: CleaningHandler, player: Player): ()
	local spills = GetSpills(player)
	if spills then
		for spillId in spills do
			spills[spillId] = nil
		end
	end

	local runtime = self.Runtime[player]
	for part, home in if runtime then runtime.Homes else {} do
		SetSpillShown(part, false)
		MoveProp(part, home)
	end

	if runtime then
		table.clear(runtime.Parts)
	end

	PlayerHandler:SetSlowed(player, false)
end

function CleaningHandler.Clean(self: CleaningHandler, player: Player, spillId: string): boolean
	local runtime = self.Runtime[player]
	local spill = runtime and runtime.Parts[spillId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not spill or not root or (root.Position - spill.Position).Magnitude > CLEAN_DISTANCE then
		return false
	end

	local held = InventoryHandler:Peek(player)
	local broomId = BuildingsConfig.Kinds.Broom.ToolId
	if not held or held.Kind ~= TOOL or held.Id ~= broomId then
		Bus.Progress.ActionFailed:FireClient(player, "need_broom")
		return false
	end

	local spills = GetSpills(player)
	if not spills or not spills[spillId] then
		return false
	end

	spills[spillId] = nil

	Bus.VFX.Burst:Fire("Cleaning", spill, spill.CFrame, player.UserId, workspace:GetServerTimeNow())
	SetSpillShown(spill, false)
	runtime.Parts[spillId] = nil

	local data = DataHandler:GetData(player)
	if data then
		data.Session.HasMopped = true
		TutorialEvents.Action:Fire(player, "Mopped", spillId)
	end
	Bus.Player.PlayAction:FireClient(player, "Sweep")
	Bus.VFX.Burst:Fire("Sweep", root, root.CFrame, player.UserId, workspace:GetServerTimeNow())

	return true
end

-- Hides every puddle in the bakery and gives each one its prompt. Called once the base is claimed,
-- so a fresh bakery starts with a clean floor whatever the artist left visible.
function CleaningHandler.PrepareSpills(self: CleaningHandler, player: Player): ()
	local kind = BuildingsConfig.Kinds[KIND_NAME]

	for index, part in GetSpillParts(player) do
		local runtime = self.Runtime[player]
		if runtime and not runtime.Homes[part] then
			runtime.Homes[part] = part.CFrame
			self:OwnSpill(runtime, part)
		end

		View.Dress(part, `{BaseConfig.SpillAnchorPrefix}_{index}`, KIND_NAME, kind, player.UserId)
		part.CanCollide = false
		SetSpillShown(part, false)
	end
end

function CleaningHandler.OwnSpill(_self: CleaningHandler, runtime: Runtime, part: BasePart): ()
	local transparency = part.Transparency
	local canCollide, canQuery, canTouch = part.CanCollide, part.CanQuery, part.CanTouch
	runtime.Janitor:Add(function(): ()
		View.Undress(part)
		MoveProp(part, runtime.Homes[part])
		part.Transparency = transparency
		part.CanCollide, part.CanQuery, part.CanTouch = canCollide, canQuery, canTouch
	end, true)
end

-- Puts one puddle on the floor: the first free model, so two spills never share a spot.
function CleaningHandler.DropSpill(self: CleaningHandler, player: Player): boolean
	local spills = GetSpills(player)
	local runtime = self.Runtime[player]
	if not spills or not runtime then
		return false
	end

	if CountSpills(spills) >= DayCycleConfig.MaxSpills then
		return false
	end

	for index, part in GetSpillParts(player) do
		local spillId = `{BaseConfig.SpillAnchorPrefix}_{index}`
		if spills[spillId] then
			continue
		end

		spills[spillId] = true
		runtime.Parts[spillId] = part
		local placement = RandomSpillCFrame(player, runtime, part)
		if placement then
			MoveProp(part, placement)
		end
		SetSpillShown(part, true)

		return true
	end

	return false
end

-- Cooking is what makes the mess: a station starting a batch may drop dough on the floor.
function CleaningHandler.OnStationWorking(self: CleaningHandler, player: Player): ()
	local spills = GetSpills(player)
	local data = DataHandler:GetData(player)
	if data and TutorialPolicy.IsActive(data.Cloud) then
		return
	end
	local firstTutorialSpill = data ~= nil
		and not data.Cloud.Tutorial.Actions.Mopped
		and spills ~= nil
		and CountSpills(spills) == 0
	if not firstTutorialSpill and math.random() > DayCycleConfig.SpillChance then
		return
	end

	self:DropSpill(player)
end

function CleaningHandler.UpdateSpills(self: CleaningHandler): ()
	for _, player in Players:GetPlayers() do
		-- A puddle underfoot slows the player down in prep as well as during the shift.
		self:UpdateSlow(player)
	end
end

function CleaningHandler.UpdateSlow(self: CleaningHandler, player: Player): ()
	local runtime = self.Runtime[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not runtime or not root then
		PlayerHandler:SetSlowed(player, false)
		return
	end

	local radius = BuildingsConfig.Kinds[KIND_NAME].Size.X / 2
	local pos = root.Position
	local slowed = false

	for _, part in runtime.Parts do
		if part.Parent then
			local delta = Vector3.new(pos.X - part.Position.X, 0, pos.Z - part.Position.Z)
			if delta.Magnitude <= radius then
				slowed = true
				break
			end
		end
	end

	PlayerHandler:SetSlowed(player, slowed)
end

export type CleaningHandler = typeof(CleaningHandler) & {
	Runtime: { [Player]: Runtime },
}

return CleaningHandler :: CleaningHandler
