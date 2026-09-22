--!strict
-- Lemon Cake's four-cart line: consume a delivery, remove its cart and advance the followers.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local Base = require(_Handlers.BaseHandler)
local Bus = require(_Shared.Bus)
local Config = require(_Shared.Configs.Garden)
local Data = require(_Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local Ingredients = require(_Shared.Configs.Registries.Ingredients)
local Inventory = require(_Handlers.InventoryHandler)
local PickupOrigin = require(script.Parent.Parent.PickupOrigin)
local RailPath = require(script.Parent.Parent.RailPath)
local Sanitize = require(_Shared.Sanitize)

--[[ Tables ]]--
local RailCart = {}

--[[ Private Functions ]]--
local function active(building: any): boolean
	local data = Data:GetData(building.Player)
	return data ~= nil and data.Session.Day.Phase ~= "Summary"
end

--[[ Handling ]]--
function RailCart.EnsureState(building: any): any?
	local data = Data:GetData(building.Player)
	local transform = Base:GetTransform(building.Player)
	building.RailPath = transform and RailPath.Read(Base.Template, transform)
	if not data or not building.RailPath then
		return nil
	end
	local state = data.Cloud.GardenCart
	for index = 1, #state.Carts do
		local cart = state.Carts[index]
		if cart.Arrived then
			cart.Distance = building.RailPath.Stops[index]
		end
	end
	return state
end

function RailCart.BuildConfig(_building: any): any
	return { initialState = "Active", states = { Active = {} }, transitions = {} }
end

function RailCart.StartDay(building: any): ()
	local data = Data:GetData(building.Player)
	if not data or building.State.Day == data.Cloud.Day then
		return
	end
	local state = building.State
	state.Queue = {}
	state.Carts = {}
	state.SpawnRemaining = 0
	state.Day = data.Cloud.Day
	-- IDs never repeat across days, so a delayed pickup cannot consume a new delivery.
	state.NextId += 1
	building.RailFeedRemaining = 0
end

function RailCart.Update(building: any, deltaTime: number, _now: number): ()
	RailCart.StartDay(building)
	if not active(building) then
		return
	end
	local state, path = building.State, building.RailPath
	building.RailFeedRemaining = math.max(0, (building.RailFeedRemaining or 0) - deltaTime)
	if state.SpawnRemaining > 0 then
		state.SpawnRemaining = math.max(0, state.SpawnRemaining - deltaTime)
	end
	for index = 1, #state.Carts do
		local cart = state.Carts[index]
		local seconds = deltaTime
		if cart.Delay > 0 then
			seconds = math.max(0, seconds - cart.Delay)
			cart.Delay = math.max(0, cart.Delay - deltaTime)
		end
		local target = path.Stops[index]
		local distance = math.min(target, cart.Distance + seconds * cart.Speed)
		if index > 1 then
			local gap = path.Stops[index - 1] - target
			distance = math.min(distance, math.max(0, state.Carts[index - 1].Distance - gap))
		end
		if distance ~= cart.Distance then
			cart.Distance = distance
		end
		local arrived = distance >= target
		if cart.Arrived ~= arrived then
			cart.Arrived = arrived
		end
	end
end

function RailCart.LoadCart(building: any): boolean
	local state = building.State
	if not active(building) or state.SpawnRemaining > 0 then
		return false
	end
	if #state.Queue >= Config.CartCapacity then
		Bus.Progress.ActionFailed:FireClient(building.Player, "cart_full")
		return false
	end
	local held = Inventory:Peek(building.Player)
	if not held or held.Kind ~= "Ingredient" or not Ingredients:Get(held.Id) then
		Bus.Progress.ActionFailed:FireClient(building.Player, "cart_produce_only")
		return false
	end
	local index = #state.Queue + 1
	state.NextId += 1
	state.Queue[index] = held.Id
	state.Carts[index] = {
		Id = `cart_{state.NextId}`,
		Distance = 0,
		Delay = Config.CartLoadSeconds,
		Speed = building.RailPath.Length / Config.CartTravelSeconds,
		Arrived = false,
	}
	state.SpawnRemaining = Config.CartLoadSeconds + Config.CartSpawnSeconds
	Inventory:Pop(building.Player)
	return true
end

-- Shared by manual pickup and the mixer's accepted ingredient transfer. Neither caller yields.
local function removeCart(building: any, index: number): ()
	local state = building.State
	for nextIndex = index + 1, #state.Carts do
		local cart = state.Carts[nextIndex]
		if cart.Arrived then
			cart.Speed = (building.RailPath.Stops[nextIndex - 1] - cart.Distance) / Config.CartShiftSeconds
		end
		cart.Arrived = false
	end
	local wasFull = #state.Queue >= Config.CartCapacity
	DataList.RemoveAt(state.Queue, index)
	-- Copy values into the new writable paths; never move a nested data proxy.
	for shift = index, #state.Carts - 1 do
		local cart = state.Carts[shift + 1]
		state.Carts[shift] =
			{ Id = cart.Id, Distance = cart.Distance, Delay = cart.Delay, Speed = cart.Speed, Arrived = cart.Arrived }
	end
	state.Carts[#state.Carts] = nil
	if wasFull then
		state.SpawnRemaining = math.max(state.SpawnRemaining, Config.CartSpawnSeconds)
	end
end

-- The output route validates ownership and range; identity also protects identical adjacent cargo.
function RailCart.TakeCart(building: any, slotIndex: number, ingredientId: string, cartId: string): boolean
	local state = building.State
	local index = Sanitize.Index(slotIndex, #state.Queue)
	if not active(building) or not index or state.Queue[index] ~= ingredientId then
		return false
	end
	local cart = state.Carts[index]
	if not cart or cart.Id ~= cartId or not cart.Arrived then
		return false
	end
	if
		not Inventory:Push(
			building.Player,
			{ Kind = "Ingredient", Id = ingredientId },
			PickupOrigin.ForDelivery(building, index)
		)
	then
		Bus.Progress.ActionFailed:FireClient(building.Player, "hands_full")
		return false
	end
	removeCart(building, index)
	return true
end

-- The owner must be at their mixer; only a needed ingredient from an arrived cart is eligible.
function RailCart.SupplyMixer(building: any, mixer: any): boolean
	if not active(building) or (building.RailFeedRemaining or 0) > 0 then
		return false
	end
	if mixer.Player ~= building.Player or not mixer.Definition.Mixes or not mixer.Behavior then
		return false
	end
	local character = building.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or (root.Position - mixer.Part.Position).Magnitude > Config.InteractionRange
	then
		return false
	end
	local state = building.State
	for index = 1, #state.Queue do
		local cart = state.Carts[index]
		if cart.Arrived and mixer.Behavior.LoadRailIngredient(mixer, state.Queue[index]) then
			removeCart(building, index)
			building.RailFeedRemaining = Config.CartFeedSeconds
			return true
		end
	end
	return false
end

return RailCart
