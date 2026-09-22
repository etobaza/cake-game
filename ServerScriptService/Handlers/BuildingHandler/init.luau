--!strict
-- Base buildings: stations, display, tables, garden, firewood and trash.
-- Builds them from the player's stats, owns the instances, drives their FSMs and routes player actions.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local Actions = require(script.Actions)
local AnimalPrompts = require(script.AnimalPrompts)
local BaseHandler = require(_Handlers.BaseHandler)
local Building = require(script.Building)
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local CafeTable = require(script.Kinds.CafeTable)
local DayCycleHandler = require(_Handlers.DayCycleHandler)
local DataHandler = require(_Handlers.DataHandler)
local DisplaySlot = require(script.Kinds.DisplaySlot)
local DispenserCarry = require(script.DispenserCarry)
local Furniture = require(script.Furniture)
local FoodSurfaceView = require(script.FoodSurfaceView)
local FoodPresentation = require(_Configs.FoodPresentation)
local GardenNode = require(script.Kinds.GardenNode)
local GardenConfig = require(_Configs.Garden)
local GardenWorld = require(script.GardenWorld)
local RailCart = require(script.Kinds.RailCart)
local RailCartView = require(script.RailCartView)
local InventoryHandler = require(_Handlers.InventoryHandler)
local LoggerUtil = require(_Libs.Logger)
local OvenView = require(script.OvenView)
local PantryHandler = require(_Handlers.PantryHandler)
local PickupOrigin = require(script.PickupOrigin)
local Recipes = require(_Configs.Registries.Recipes)
local Sanitize = require(_Shared.Sanitize)
local Signal = require(_Libs.Signal)
local Station = require(script.Kinds.Station)
local TickHandler = require(_Handlers.TickHandler)
local TutorialEvents = require(ServerScriptService.TutorialEvents)
local TrashView = require(script.TrashView)
local TableMenuView = require(script.TableMenuView)
local UpgradeHandler = require(_Handlers.UpgradeHandler)
local View = require(script.View)

--[[ Constants ]]--
local FOLDER_NAME = "Props"
-- Janitor key of the "this tool is in someone's hands" hiding, so putting it back is one Remove.
local CARRIED_KEY = "Carried"
-- Slightly beyond the prompt's 12-stud activation radius to allow for replication latency.
local REMOTE_DISTANCE = 14

-- Building class from the config -> behavior module. No class here means the building is view only.
local BEHAVIORS = {
	Station = Station,
	CafeTable = CafeTable,
	DisplaySlot = DisplaySlot,
	GardenNode = GardenNode,
	RailCart = RailCart,
}

local VISUALS = {
	Oven = OvenView,
	RailCart = RailCartView,
	Trash = TrashView,
	TableMenus = TableMenuView,
}

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "BuildingHandler" })

--[[ Tables ]]--
local BuildingHandler = {
	dependencies = {
		"DataHandler",
		"BaseHandler",
		-- Parts name a collision group as they are built, and the groups are registered there.
		"CollisionHandler",
		"UpgradeHandler",
		"TickHandler",
		"InventoryHandler",
		"DayCycleHandler",
		"PantryHandler",
		"PlayerHandler",
	},
	-- The base must already stand, hence later than BaseHandler.
	priority = 40,
}

export type PlayerBuildings = {
	Root: Folder,
	Folder: Folder,
	Transform: CFrame,
	Buildings: { [string]: Building.Building },
	-- Artist copies hidden for spawned slots, restored when the base unloads.
	Hidden: { Furniture.Hidden },
	GardenWorld: GardenWorld.GardenWorld?,
}

-- Fired after a building changed its state: (player, building, newState, oldState).
BuildingHandler.StateChanged = Signal() :: Signal.Signal<Player, any, string, string?>

--[[ Private Functions ]]--
-- Floor point named in the template's Anchors folder.
local function ResolveAnchor(template: Instance, buildingId: string): CFrame?
	local folder = template:FindFirstChild(BaseConfig.AnchorsFolderName)
	local part = folder and folder:FindFirstChild(buildingId)

	return if part and part:IsA("BasePart") then part.CFrame else nil
end

local function HasLoadedIngredients(state: any): boolean
	for _, amount in state.Loaded or {} do
		if amount > 0 then
			return true
		end
	end

	return false
end

local function IngredientId(building: Building.Building): string?
	local prefix = building.Definition.Prefix
	return prefix and string.match(building.Id, `^{prefix}_(.+)$`)
end

--[[ Handling ]]--
function BuildingHandler.OnInit(self: BuildingHandler): ()
	self.Bases = {}
end

function BuildingHandler.OnStart(self: BuildingHandler): ()
	BaseHandler.BaseReady:Connect(function(player: Player, root: Folder)
		self:Build(player, root)
	end)

	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:Unload(player)
	end)

	-- An upgrade added an oven or a plot — it has to show up in the world right away.
	UpgradeHandler.StatsChanged:Connect(function(player: Player)
		self:Refresh(player)
	end)

	DayCycleHandler.DayStarted:Connect(function(player: Player)
		self:Broadcast(player, "StartDay")
	end)

	-- A tool that is being carried must not also stand on its rack.
	InventoryHandler.ToolTaken:Connect(function(player: Player, buildingId: string)
		self:SetCarried(player, buildingId, true)
	end)

	InventoryHandler.ToolReturned:Connect(function(player: Player, buildingId: string)
		self:SetCarried(player, buildingId, false)
	end)

	-- The base may have gone up before this handler subscribed to the signal.
	for _, player in Players:GetPlayers() do
		local model = BaseHandler:GetBase(player)
		if model then
			self:Build(player, model)
		end
	end

	TickHandler.Tick:Connect(function(deltaTime: number)
		self:Update(deltaTime)
	end)

	Actions.Bind(self)
end

-- Slot number from a packet, checked against how many slots of that kind the player owns.
function BuildingHandler.SanitizeSlot(_self: BuildingHandler, player: Player, kindName: string, slotIndex: any): number?
	local stat = BuildingsConfig.Kinds[kindName].Stat :: any

	return Sanitize.Index(slotIndex, UpgradeHandler:GetStat(player, stat))
end

function BuildingHandler.Build(self: BuildingHandler, player: Player, root: Folder): ()
	if self.Bases[player] then
		return
	end

	local transform = BaseHandler:GetTransform(player)
	if not transform then
		Logger:Warn(`No transform for {player.Name}, buildings skipped`)
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = root

	local data = DataHandler:GetData(player)
	self.Bases[player] = {
		Root = root,
		Folder = folder,
		Transform = transform,
		Buildings = {},
		Hidden = {},
		GardenWorld = if data then GardenWorld.new(root, folder, data, BaseHandler.Template, transform) else nil,
	}

	self:Refresh(player)
end

function BuildingHandler.Unload(self: BuildingHandler, player: Player): ()
	local base = self.Bases[player]
	if not base then
		return
	end

	for _, building in base.Buildings do
		-- A tool still in the player's hands comes back onto its stand first: the Janitor drains in no
		-- particular order, and undressing an authored model before that would leave it invisible.
		building.Janitor:Remove(CARRIED_KEY)
		building.Janitor:Remove("DispenserCarry")
		building:Destroy()
	end

	-- The bakery itself stays in the world: put the artist copies back.
	if base.GardenWorld then
		base.GardenWorld:Destroy()
	end
	Furniture.Restore(base.Hidden)
	base.Folder:Destroy()

	self.Bases[player] = nil
end

-- Adds what is missing. Existing buildings are left alone: they may be busy.
function BuildingHandler.Refresh(self: BuildingHandler, player: Player): ()
	local base = self.Bases[player]
	if not base then
		return
	end

	for kindName, kind in BuildingsConfig.Kinds do
		self:SpawnGroup(player, kindName, kind)
		self:SpawnSingles(player, kindName, kind)
	end
	self:RefreshDisplayPlacement(player)
end

-- Slots remain a dense inventory array. Bonus capacity uses the permanent ledge until the player
-- buys pedestal upgrades; moving a display never changes or discards the dish stored in that slot.
function BuildingHandler.RefreshDisplayPlacement(self: BuildingHandler, player: Player): ()
	local base = self.Bases[player]
	if not base then
		return
	end
	local bought = math.clamp(
		UpgradeHandler:GetLevel(player, FoodPresentation.DisplayUpgrade),
		0,
		FoodPresentation.DisplayPedestals
	)
	local anchors = BaseHandler.Template:FindFirstChild(BaseConfig.AnchorsFolderName)
	for _, building in base.Buildings do
		if building.Kind ~= "Display" then
			continue
		end
		local physical = if building.Index <= bought + 1
			then building.Index
			else FoodPresentation.DisplayPedestals + building.Index - bought
		local anchor = anchors and anchors:FindFirstChild(`display_{physical}`)
		if not anchor or not anchor:IsA("BasePart") then
			continue
		end
		building.Part.CFrame = base.Transform * anchor.CFrame * CFrame.new(0, building.Definition.Size.Y / 2, 0)
		local surface = anchor:FindFirstChild(FoodPresentation.SurfaceAttachment)
		if building.FoodVisual and surface and surface:IsA("Attachment") then
			building.FoodVisual:SetFrame(base.Transform * surface.WorldCFrame)
		end
	end
end

-- Group buildings: how many of them exist is decided by a stat, capped by how many anchors exist.
function BuildingHandler.SpawnGroup(
	self: BuildingHandler,
	player: Player,
	kindName: string,
	kind: BuildingsConfig.Kind
): ()
	if kind.Class == "GardenNode" then
		for id, source in GardenConfig.Sources do
			if source.Kind ~= kindName or UpgradeHandler:GetLevel(player, source.Upgrade) <= 0 then
				continue
			end
			self:Spawn(player, id, kindName, kind)
		end
		return
	end
	if not kind.Stat or not kind.Prefix then
		return
	end

	local stat = UpgradeHandler:GetStat(player, kind.Stat :: any)
	local slots = BaseHandler:CountAnchors(kind.Prefix)

	for purchase = 1, math.min(stat, slots) do
		-- The Nth thing bought does not have to stand at anchor N: the shop order and the artist's
		-- layout differ for the trees and the animals.
		local index = if kind.SlotOrder then kind.SlotOrder[purchase] else purchase
		if not index or index > slots then
			continue
		end

		local slotFurniture = kind.FurnitureByIndex and kind.FurnitureByIndex[index]
		self:Spawn(player, `{kind.Prefix}_{index}`, kindName, kind, slotFurniture)
	end
end

function BuildingHandler.SpawnSingles(
	self: BuildingHandler,
	player: Player,
	kindName: string,
	kind: BuildingsConfig.Kind
): ()
	if kind.RequiredUpgrade and UpgradeHandler:GetLevel(player, kind.RequiredUpgrade) <= 0 then
		return
	end
	for _, single in (kind.Singles or {}) :: { BuildingsConfig.Single } do
		self:Spawn(player, single.Id, kindName, kind, single.Furniture, single.WorldModel)
	end
end

-- The part a building lives on. A kind that names an authored model takes that model over -- prompt,
-- attributes and tag go onto what the artist drew, and nothing of ours is built. Everything else gets
-- the usual block on its anchor.
function BuildingHandler.BuildPart(
	self: BuildingHandler,
	player: Player,
	base: PlayerBuildings,
	buildingId: string,
	kindName: string,
	kind: BuildingsConfig.Kind,
	furniture: BuildingsConfig.Furniture?,
	worldModel: { string }?
): BasePart?
	local path = worldModel or kind.WorldModel
	if path then
		return self:DressAuthored(player, buildingId, kindName, kind, path)
	end

	local anchor = ResolveAnchor(BaseHandler.Template, buildingId)
	if kindName == "RailOutput" then
		local anchors = BaseHandler.Template:FindFirstChild(BaseConfig.AnchorsFolderName)
		local output = anchors and anchors:FindFirstChild("rail_output")
		local index = math.max(1, BuildingsConfig.GetIndex(buildingId))
		local point = output and output:FindFirstChild(`GardenProduce{5 - index}`)
		-- View.Create lifts floor anchors by half the part height; these points are already on the trays.
		anchor = if point and point:IsA("Attachment")
			then point.WorldCFrame * CFrame.new(0, -kind.Size.Y / 2, 0)
			else nil
	end
	if not anchor then
		Logger:Warn(`No anchor {buildingId}, skipped`)
		return nil
	end

	local placement = base.Transform * anchor
	local part = View.Create(buildingId, kindName, kind, placement, player.UserId, BaseHandler.Template, furniture)
	part.Parent = base.Folder

	return part
end

-- Hangs the prompt on a model the artist drew. A path may address a Model, in which case the first
-- part inside it carries the prompt: the whole point is that we do not rebuild the thing.
function BuildingHandler.DressAuthored(
	_self: BuildingHandler,
	player: Player,
	buildingId: string,
	kindName: string,
	kind: BuildingsConfig.Kind,
	path: { string }
): BasePart?
	local bakery = BaseHandler:GetBase(player)
	local target = bakery and BuildingsConfig.ResolvePath(bakery, path)
	local part = if target and target:IsA("BasePart")
		then target
		else target and target:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		Logger:Warn(`No authored model {table.concat(path, ".")} for {buildingId}, skipped`)
		return nil
	end

	if part:GetAttribute(BuildingsConfig.IdAttribute) then
		Logger:Warn(
			`{part.Name} already carries {part:GetAttribute(BuildingsConfig.IdAttribute)}, {buildingId} skipped`
		)
		return nil
	end

	View.Dress(part, buildingId, kindName, kind, player.UserId)

	return part
end

function BuildingHandler.Spawn(
	self: BuildingHandler,
	player: Player,
	buildingId: string,
	kindName: string,
	kind: BuildingsConfig.Kind,
	furniture: BuildingsConfig.Furniture?,
	worldModel: { string }?
): ()
	local base = self.Bases[player]
	if not base or base.Buildings[buildingId] then
		return
	end

	local part = self:BuildPart(player, base, buildingId, kindName, kind, furniture, worldModel)
	if not part then
		return
	end

	if kind.SeatsFromAnchors then
		local anchors = BaseHandler.Template:FindFirstChild(BaseConfig.AnchorsFolderName)
		local anchor = anchors and anchors:FindFirstChild(buildingId)
		if not anchor or not View.AttachSeats(part, anchor, base.Transform) then
			Logger:Warn(`Missing authored guest seats for {buildingId}`)
		end
	end

	local building = Building.new(player, buildingId, kindName, kind, BEHAVIORS[kind.Class], part)
	base.Buildings[buildingId] = building
	AnimalPrompts.Attach(building, BaseHandler.Template, base.Transform)
	if kindName == "Ingredient" then
		building.Janitor:Add(DispenserCarry.new(building), "Destroy", "DispenserCarry")
	end
	local foodVisual = FoodSurfaceView.new(base.Root, building)
	if foodVisual then
		building.FoodVisual = foodVisual
		building.Janitor:Add(foodVisual, "Destroy", "FoodVisual")
	end

	local visualClass = kind.Visual and VISUALS[kind.Visual]
	local visual = visualClass and visualClass.new(base.Root, building)
	if visual then
		building:SetVisual(visual)
	elseif kind.Visual then
		Logger:Warn(`No authored {kind.Visual} visual for {buildingId}`)
	end

	-- An authored model outlives the claim: what was hung on it comes off when the bakery is released.
	if part.Parent ~= base.Folder then
		building.Janitor:Add(function()
			View.Undress(part)
		end, true)
	end

	if not building.FSM then
		return
	end

	local connection = building.FSM.onStateChange:Connect(function(newState: any, oldState: any)
		self.StateChanged:Fire(player, building, newState.name, oldState and oldState.name)
	end)

	building.Janitor:Add(connection, "Disconnect")
end

-- Hides the model of a tool while it is in the player's hands, and puts it back when it is returned.
-- For the broom that model is the artist's own, standing in the kitchen; the block beside it keeps
-- its prompt either way, so the empty spot can still be used. The restore rides on the building's
-- Janitor: releasing the bakery brings the tool back on its own.
function BuildingHandler.SetCarried(self: BuildingHandler, player: Player, buildingId: string, carried: boolean): ()
	local building = self:GetBuilding(player, buildingId)
	if not building then
		return
	end

	if not carried then
		building.Janitor:Remove(CARRIED_KEY)
		return
	end

	if building.Janitor:Get(CARRIED_KEY) then
		return
	end

	local model = BuildingsConfig.WorldModel(building.Part) or building.Part

	local hidden: { Furniture.Hidden } = {}
	Furniture.Hide(model, hidden)

	building.Janitor:Add(function()
		Furniture.Restore(hidden)
	end, true, CARRIED_KEY)
end

function BuildingHandler.Update(self: BuildingHandler, deltaTime: number): ()
	local now = workspace:GetServerTimeNow()

	for player, base in self.Bases do
		local data = DataHandler:GetData(player)
		local day = data and data.Session.Day
		local paused = day ~= nil and day.Phase == "Summary"
		local simulationTime = if paused and day then day.SummaryStartedAt else now
		for _, building in base.Buildings do
			building:Update(if paused then 0 else deltaTime, simulationTime, paused)
		end
		local cart = base.Buildings.rail_cart
		if not paused and cart and cart.State and cart.Behavior then
			for _, mixer in base.Buildings do
				if mixer.Definition.Mixes and cart.Behavior.SupplyMixer(cart, mixer) then
					TutorialEvents.Action:Fire(player, "Load", mixer.Id)
					break
				end
			end
		end
		if base.GardenWorld then
			base.GardenWorld:Update(deltaTime, now)
		end
	end
end

function BuildingHandler.GetBuilding(self: BuildingHandler, player: Player, buildingId: string): Building.Building?
	local base = self.Bases[player]

	return base and base.Buildings[buildingId]
end

function BuildingHandler.GetBuildings(self: BuildingHandler, player: Player): { [string]: Building.Building }
	local base = self.Bases[player]

	return if base then base.Buildings else {}
end

-- The recipe strip is only an intent. The server verifies menu membership, ownership of the target
-- station, and that changing the choice cannot strand ingredients already sitting in a mixer.
function BuildingHandler.SelectRecipe(self: BuildingHandler, player: Player, recipeId: string): boolean
	if DayCycleHandler:GetPhase(player) == "Summary" then
		return false
	end
	local recipe = Recipes:Get(recipeId)
	local data = DataHandler:GetData(player)
	if not recipe or not data then
		return false
	end

	if not DayCycleHandler:IsOnMenu(player, recipeId) then
		Bus.Progress.ActionFailed:FireClient(player, "not_on_menu")
		return false
	end

	local hasStartStation = false
	for _, building in self:GetBuildings(player) do
		if building.Kind == Recipes:GetStartStation(recipe) then
			hasStartStation = true
		end

		if building.Definition.Mixes and building.State and HasLoadedIngredients(building.State) then
			local selected = data.Session.Cooking.SelectedRecipeId
			if selected ~= recipeId then
				Bus.Progress.ActionFailed:FireClient(player, "mixer_has_ingredients")
				return false
			end
		end
	end

	if not hasStartStation then
		Bus.Progress.ActionFailed:FireClient(player, "station_missing")
		return false
	end

	data.Session.Cooking.SelectedRecipeId = recipeId
	TutorialEvents.Action:Fire(player, "SelectRecipe", recipeId)

	return true
end

-- Every prop packet passes through the same ownership, kind and distance gate before it can mutate
-- inventory or station state. A missing building is intentionally reported like an out-of-range one.
function BuildingHandler.ValidateRemoteBuilding(
	self: BuildingHandler,
	player: Player,
	buildingId: string,
	expectedKind: string?
): Building.Building?
	if DayCycleHandler:GetPhase(player) == "Summary" then
		return nil
	end
	local building = self:GetBuilding(player, buildingId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not building
		or not root
		or not humanoid
		or humanoid.Health <= 0
		or (root.Position - building.Part.Position).Magnitude > REMOTE_DISTANCE
	then
		Bus.Progress.ActionFailed:FireClient(player, "too_far")
		return nil
	end

	if expectedKind and building.Kind ~= expectedKind then
		Bus.Progress.ActionFailed:FireClient(player, "wrong_station")
		return nil
	end

	return building
end

-- The entrance is a normal ranged building interaction; DayCycleHandler remains the only phase owner.
function BuildingHandler.ToggleDoor(self: BuildingHandler, player: Player, doorId: string): boolean
	if not self:ValidateRemoteBuilding(player, doorId, "Door") then
		return false
	end

	return DayCycleHandler:ToggleBakery(player)
end

function BuildingHandler.Discard(self: BuildingHandler, player: Player, trashId: string): boolean
	local building = self:ValidateRemoteBuilding(player, trashId, "Trash")
	if not building then
		return false
	end

	local data = DataHandler:GetData(player)
	local held = data and data.Session.Hands[1]
	local burnt = held and held.Kind == "Burnt"
	if not InventoryHandler:Discard(player) then
		return false
	end
	if burnt then
		TutorialEvents.Action:Fire(player, "DisposeBurnt", trashId)
	end

	local visual = building.Visual
	local play = visual and visual.Play
	if play then
		play(visual)
	end

	return true
end

function BuildingHandler.TakeCartDelivery(
	self: BuildingHandler,
	player: Player,
	id: string,
	ingredientId: string,
	cartId: string
): boolean
	local output = self:ValidateRemoteBuilding(player, id, "RailOutput")
	if not output then
		return false
	end
	local accepted = self:Dispatch(player, "rail_cart", "TakeCart", math.max(1, output.Index), ingredientId, cartId)
		== true
	if accepted then
		TutorialEvents.Action:Fire(player, "TakeCart", id)
	end
	return accepted
end

function BuildingHandler.UseToolRack(self: BuildingHandler, player: Player, id: string, action: string): ()
	local building = self:ValidateRemoteBuilding(player, id)
	if not building or not building.Definition.ToolId then
		return
	end
	if action == "TakeTool" then
		InventoryHandler:TakeTool(player, id, PickupOrigin.ForBuilding(building))
	elseif action == "ReturnTool" then
		InventoryHandler:ReturnTool(player, id)
	end
end

function BuildingHandler.TakeFirewood(self: BuildingHandler, player: Player, pileId: string): boolean
	local building = self:ValidateRemoteBuilding(player, pileId, "Fuel")
	if not building or not building.Definition.GivesFuel then
		return false
	end

	return InventoryHandler:TakeFirewood(player, pileId, PickupOrigin.ForBuilding(building))
end

function BuildingHandler.TakeIngredient(self: BuildingHandler, player: Player, dispenserId: string): boolean
	local building = self:ValidateRemoteBuilding(player, dispenserId, "Ingredient")
	local ingredientId = building and IngredientId(building)
	if not building or not ingredientId then
		return false
	end
	if not PantryHandler:Take(player, ingredientId, dispenserId, PickupOrigin.ForBuilding(building)) then
		return false
	end

	return true
end

function BuildingHandler.ReturnIngredient(self: BuildingHandler, player: Player, dispenserId: string): boolean
	local building = self:ValidateRemoteBuilding(player, dispenserId, "Ingredient")
	local ingredientId = building and IngredientId(building)
	if not building or not ingredientId then
		return false
	end
	return InventoryHandler:ReturnIngredient(player, dispenserId, ingredientId)
end

function BuildingHandler.DispatchRemote(
	self: BuildingHandler,
	player: Player,
	buildingId: string,
	action: string,
	...: any
): any
	if not self:ValidateRemoteBuilding(player, buildingId) then
		return
	end

	local result = self:Dispatch(player, buildingId, action, ...)
	if result == true then
		TutorialEvents.Action:Fire(player, action, buildingId)
	end
	return result
end

function BuildingHandler.Dispatch(
	self: BuildingHandler,
	player: Player,
	buildingId: string,
	action: string,
	...: any
): any
	local building = self:GetBuilding(player, buildingId)
	local behavior = building and building.Behavior
	local perform = behavior and behavior[action]
	if not building or not perform or not building.State then
		return
	end

	return perform(building, ...)
end

-- Same action over every building that knows it: this is how the day change reaches them all.
function BuildingHandler.Broadcast(self: BuildingHandler, player: Player, action: string, ...: any): ()
	for buildingId in self:GetBuildings(player) do
		self:Dispatch(player, buildingId, action, ...)
	end
end

-- Takes the first finished dish past the player's hands: used by the assistant.
function BuildingHandler.TakeReadyDish(self: BuildingHandler, player: Player): string?
	for _, building in self:GetBuildings(player) do
		local behavior = building.Behavior
		local takeReady = behavior and behavior.TakeReady
		local recipeId = if takeReady and building.State then takeReady(building) else nil

		if recipeId then
			return recipeId
		end
	end

	return
end

-- First building of a kind whose machine sits in one of the wanted states.
function BuildingHandler.FindInState(
	self: BuildingHandler,
	player: Player,
	kindName: string,
	stateName: string
): Building.Building?
	for _, building in self:GetBuildings(player) do
		if building.Kind == kindName and building:GetState() == stateName then
			return building
		end
	end

	return
end

export type BuildingHandler = typeof(BuildingHandler) & {
	Bases: { [Player]: PlayerBuildings },
}

return BuildingHandler :: BuildingHandler
