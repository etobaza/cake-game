--!strict
-- Which packet triggers which building action. Adding an action is one row here, not a new listener.
-- Every route validates its argument before the handler dispatches it to the building.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local Sanitize = require(_Shared.Sanitize)

--[[ Constants ]]--
-- Packets that name the building directly.
local BY_ID = {
	{ Packet = Bus.Kitchen.Mix, Action = "Mix" },
	{ Packet = Bus.Kitchen.Load, Action = "Load" },
	{ Packet = Bus.Kitchen.Cancel, Action = "Cancel" },
	{ Packet = Bus.Kitchen.Collect, Action = "Collect" },
	{ Packet = Bus.Kitchen.Refuel, Action = "Refuel" },
	{ Packet = Bus.Garden.Water, Action = "Tend" },
	{ Packet = Bus.Garden.Brush, Action = "Tend" },
	{ Packet = Bus.Garden.Harvest, Action = "Harvest" },
	{ Packet = Bus.Garden.CartLoad, Action = "LoadCart" },
}

-- Display packets carry a slot number instead of a building id.
local BY_SLOT = {
	{ Packet = Bus.Cafe.DisplayPlace, Action = "Place", Kind = "Display" },
	{ Packet = Bus.Cafe.DisplayTake, Action = "Take", Kind = "Display" },
}

--[[ Tables ]]--
local Actions = {}

--[[ Private Functions ]]--
local function BindById(handler: any, route: any): ()
	route.Packet.OnServerEvent:Connect(function(player: Player, buildingId: any)
		local id = Sanitize.Id(buildingId)
		if not id then
			return
		end

		handler:DispatchRemote(player, id, route.Action)
	end)
end

local function BindBySlot(handler: any, route: any): ()
	route.Packet.OnServerEvent:Connect(function(player: Player, slotIndex: any)
		local index = handler:SanitizeSlot(player, route.Kind, slotIndex)
		if not index then
			return
		end

		handler:DispatchRemote(player, BuildingsConfig.GetId(route.Kind, index), route.Action)
	end)
end

local function BindRecipe(handler: any): ()
	Bus.Kitchen.SelectRecipe.OnServerEvent:Connect(function(player: Player, recipeId: any)
		local recipe = Sanitize.Id(recipeId)
		if recipe then
			handler:SelectRecipe(player, recipe)
		end
	end)

	Bus.Kitchen.TakePantry.OnServerEvent:Connect(function(player: Player, stationId: any, ingredientId: any)
		local station = Sanitize.Id(stationId)
		local ingredient = Sanitize.Id(ingredientId)
		if station and ingredient then
			handler:DispatchRemote(player, station, "TakePantry", ingredient)
		end
	end)
end

local function BindDoor(handler: any): ()
	Bus.Day.ToggleDoor.OnServerEvent:Connect(function(player: Player, doorId: any)
		local id = Sanitize.Id(doorId)
		if id then
			handler:ToggleDoor(player, id)
		end
	end)
end

local function BindProps(handler: any): ()
	for _, action in { "TakeTool", "ReturnTool" } do
		Bus.Cafe[action].OnServerEvent:Connect(function(player: Player, value: any)
			local id = Sanitize.Id(value)
			if id then
				handler:UseToolRack(player, id, action)
			end
		end)
	end
	Bus.Kitchen.TakeIngredient.OnServerEvent:Connect(function(player: Player, dispenserId: any)
		local id = Sanitize.Id(dispenserId)
		if id then
			handler:TakeIngredient(player, id)
		end
	end)

	Bus.Kitchen.ReturnIngredient.OnServerEvent:Connect(function(player: Player, dispenserId: any)
		local id = Sanitize.Id(dispenserId)
		if id then
			handler:ReturnIngredient(player, id)
		end
	end)

	Bus.Kitchen.Trash.OnServerEvent:Connect(function(player: Player, trashId: any)
		local id = Sanitize.Id(trashId)
		if id then
			handler:Discard(player, id)
		end
	end)

	Bus.Kitchen.TakeFirewood.OnServerEvent:Connect(function(player: Player, pileId: any)
		local id = Sanitize.Id(pileId)
		if id then
			handler:TakeFirewood(player, id)
		end
	end)
end

--[[ Handling ]]--
function Actions.Bind(handler: any): ()
	Bus.Garden.CartTake.OnServerEvent:Connect(
		function(player: Player, value: any, expectedIngredient: any, expectedCart: any)
			local id = Sanitize.Id(value)
			local ingredientId = Sanitize.Id(expectedIngredient)
			local cartId = Sanitize.Id(expectedCart)
			if id and ingredientId and cartId then
				handler:TakeCartDelivery(player, id, ingredientId, cartId)
			end
		end
	)
	for _, route in BY_ID do
		BindById(handler, route)
	end

	for _, route in BY_SLOT do
		BindBySlot(handler, route)
	end

	BindRecipe(handler)
	BindDoor(handler)
	BindProps(handler)
end

return Actions
