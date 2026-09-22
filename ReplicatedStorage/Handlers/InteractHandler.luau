--!strict
-- World interaction: keeps the prompts and labels of the player's own buildings up to date
-- and sends the intent when one is triggered.
-- What each building says and fires lives in Shared/BuildingViews; this handler only routes.

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers
local _Views = _Shared.BuildingViews

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local BuildingsConfig = require(_Configs.Buildings)
local GardenConfig = require(_Configs.Garden)
local DataClient = require(_Handlers.DataHandlerClient)
local Ingredients = require(_Configs.Registries.Ingredients)
local Recipes = require(_Configs.Registries.Recipes)
local Types = require(_Views.Types)

--[[ Constants ]]--
-- Some labels are countdowns, so we redraw on a timer instead of on data change.
local REFRESH_INTERVAL = 0.2

-- Views without Paint are cast because the solver treats a missing optional field as a mismatch.
local VIEWS: { [string]: Types.View } = {
	CafeTable = require(_Views.CafeTable) :: Types.View,
	DisplaySlot = require(_Views.DisplaySlot) :: Types.View,
	Dispenser = require(_Views.Dispenser) :: Types.View,
	Door = require(_Views.Door) :: Types.View,
	FuelPile = require(_Views.FuelPile) :: Types.View,
	GardenNode = require(_Views.GardenNode) :: Types.View,
	RailCart = require(_Views.RailCart) :: Types.View,
	Spill = require(_Views.Spill) :: Types.View,
	Station = require(_Views.Station) :: Types.View,
	ToolRack = require(_Views.ToolRack) :: Types.View,
	TrashBin = require(_Views.TrashBin) :: Types.View,
}

--[[ Tables ]]--
local InteractHandler = {
	dependencies = { "DataClient" },
}

--[[ Private Functions ]]--
local function Session(key: string): any?
	return DataClient:GetData({ key }, "Session")
end

local function Cloud(path: { string }): any?
	return DataClient:GetData(path)
end

-- Last item in hands: putting down and picking up works off the end of the stack.
local function Held(): any?
	local hands = Session("Hands")

	return if hands then hands[#hands] else nil
end

local function RecipeName(recipeId: string?): string
	local recipe = recipeId and Recipes:Get(recipeId)

	return if recipe then recipe.name else "Something"
end

local function ItemName(item: any): string
	if item.Kind == "Leftover" then
		return "Leftover Pastry"
	end
	if item.Kind == "Ingredient" then
		local ingredient = Ingredients:Get(item.Id)
		return if ingredient then ingredient.name else item.Id
	end

	if item.Kind == "Tool" then
		return BuildingsConfig.ToolLabel(item.Id)
	end

	if item.Kind == "Fuel" then
		return BuildingsConfig.FuelLabel()
	end

	local recipe = Recipes:Get(item.Id)
	local name = if recipe then recipe.name else item.Id
	if item.Kind == "Dough" then
		return `{name} dough`
	end

	if item.Kind == "Burnt" then
		return `burnt {name}`
	end

	return name
end

local function Seconds(deadline: number): number
	return math.max(math.ceil(deadline - workspace:GetServerTimeNow()), 0)
end

local function ResolveView(kindName: string): {
	Describe: (Types.Context) -> Types.PromptState,
	Paint: ((BasePart, Types.Context) -> ())?,
}?
	local kind = BuildingsConfig.Kinds[kindName]

	return if kind then VIEWS[kind.View or kind.Class] else nil
end

local function BuildContext(propId: string, kindName: string, part: BasePart): Types.Context
	return {
		PropId = propId,
		Kind = kindName,
		AnimalAction = part:GetAttribute(GardenConfig.AnimalActionAttribute) :: string?,
		Index = BuildingsConfig.GetIndex(propId),
		Session = Session,
		Cloud = Cloud,
		Held = Held,
		RecipeName = RecipeName,
		ItemName = ItemName,
		Seconds = Seconds,
	}
end

--[[ Handling ]]--
function InteractHandler.OnInit(self: InteractHandler): ()
	self.Props = {}
	self.UserId = Players.LocalPlayer.UserId
	self.Accumulator = 0
end

function InteractHandler.OnStart(self: InteractHandler): ()
	for _, instance in CollectionService:GetTagged(BuildingsConfig.Tag) do
		self:Track(instance)
	end

	CollectionService:GetInstanceAddedSignal(BuildingsConfig.Tag):Connect(function(instance: Instance)
		self:Track(instance)
	end)

	CollectionService:GetInstanceRemovedSignal(BuildingsConfig.Tag):Connect(function(instance: Instance)
		self.Props[instance] = nil
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == Players.LocalPlayer then
			self:Trigger(prompt.Parent)
		end
	end)

	DataClient:WaitForData()

	RunService.Heartbeat:Connect(function(deltaTime: number)
		self.Accumulator += deltaTime
		if self.Accumulator < REFRESH_INTERVAL then
			return
		end

		self.Accumulator = 0
		self:RefreshAll()
	end)
end

-- Other players' bases are of no use: they are not shown and their prompts stay off.
function InteractHandler.Track(self: InteractHandler, instance: Instance): ()
	if instance:IsA("BasePart") and instance:GetAttribute(BaseConfig.OwnerAttribute) == self.UserId then
		self.Props[instance] = true
		if DataClient:IsReady() then
			self:RefreshProp(instance)
		end
	end
end

-- Own building by id: this is how the tutorial guide finds where to point.
function InteractHandler.GetProp(self: InteractHandler, propId: string): BasePart?
	for part in self.Props do
		if
			part.Parent
			and part:GetAttribute(BuildingsConfig.IdAttribute) == propId
			and part:GetAttribute(GardenConfig.AnimalActionAttribute) ~= "Harvest"
		then
			return part :: BasePart
		end
	end

	return nil
end

-- A read-only snapshot for guidance; callers never reach into the tracking dictionary.
function InteractHandler.GetOwnedIds(self: InteractHandler): { [string]: boolean }
	local ids = {}
	for part in self.Props do
		if not part.Parent then
			continue
		end
		local id = part:GetAttribute(BuildingsConfig.IdAttribute)
		if typeof(id) == "string" then
			ids[id] = true
		end
	end
	return ids
end

function InteractHandler.RefreshAll(self: InteractHandler): ()
	if not DataClient:IsReady() then
		return
	end

	for part in self.Props do
		if part.Parent then
			self:RefreshProp(part :: BasePart)
		else
			self.Props[part] = nil
		end
	end
end

function InteractHandler.RefreshProp(self: InteractHandler, part: BasePart): ()
	local propId = part:GetAttribute(BuildingsConfig.IdAttribute) :: string
	local kindName = part:GetAttribute(BuildingsConfig.KindAttribute) :: string
	local view = ResolveView(kindName)
	local context = BuildContext(propId, kindName, part)
	local state: Types.PromptState = if view then view.Describe(context) else { Label = kindName }
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	local kind = BuildingsConfig.Kinds[kindName]

	-- Recolouring happens on the client only, so it costs no replication and shows just the owner.
	if kind and not BuildingsConfig.WorldModel(part) then
		part.Color = state.Tint or kind.Color
	end

	-- There is no floating label anymore: the status line rides on the prompt plate instead, so
	-- countdowns like the oven's stay visible to whoever stands at the station.
	if prompt then
		prompt.Enabled = state.Action ~= nil
		prompt.ActionText = state.Action or ""
		prompt.ObjectText = state.Label
		prompt.HoldDuration = 0
	end

	if view and view.Paint then
		view.Paint(part, context)
	end

	self:HideHeldTool(part, kind)
end

-- The stand's mesh hides while that tool is in the player's hands, so it looks taken.
function InteractHandler.HideHeldTool(_self: InteractHandler, part: BasePart, kind: any): ()
	if not kind or not kind.ToolId then
		return
	end

	local held = Held()
	local taken = held ~= nil and held.Kind == "Tool" and held.Id == kind.ToolId
	local modifier = if taken then 1 else 0

	for _, piece in part:GetDescendants() do
		if piece:IsA("BasePart") and piece ~= part then
			piece.LocalTransparencyModifier = modifier
		end
	end
end

function InteractHandler.Trigger(self: InteractHandler, instance: Instance?): ()
	if not instance or not self.Props[instance] then
		return
	end

	local state = self:Describe(instance :: BasePart)
	if state.Fire then
		state.Fire()
	end
end

function InteractHandler.Describe(_self: InteractHandler, part: BasePart): Types.PromptState
	local propId = part:GetAttribute(BuildingsConfig.IdAttribute) :: string
	local kindName = part:GetAttribute(BuildingsConfig.KindAttribute) :: string
	local view = ResolveView(kindName)

	if not view then
		return { Label = kindName }
	end

	return view.Describe(BuildContext(propId, kindName, part))
end

export type InteractHandler = typeof(InteractHandler) & {
	Props: { [Instance]: boolean },
	UserId: number,
	Accumulator: number,
}

return InteractHandler :: InteractHandler
