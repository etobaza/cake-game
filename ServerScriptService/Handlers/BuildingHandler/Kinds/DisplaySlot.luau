--!strict
-- Display slot: Empty <-> Filled. The dish itself is the state, so the machine follows the data
-- instead of mirroring a separate field.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local DataHandler = require(_Handlers.DataHandler)
local GameTypes = require(_Shared.GameTypes)
local InventoryHandler = require(_Handlers.InventoryHandler)
local PickupOrigin = require(script.Parent.Parent.PickupOrigin)

--[[ Tables ]]--
local DisplaySlot = {}

--[[ Private Functions ]]--
-- A slot's leftover flag is either set or absent, never stored as false.
local function SetLeftover(leftovers: { [number]: boolean }, index: number, isLeftover: boolean): ()
	if isLeftover then
		leftovers[index] = true
	else
		leftovers[index] = nil
	end
end

--[[ Handling ]]--
-- The whole shelf is one table keyed by slot index, so the node is the shelf and Index is the key.
function DisplaySlot.EnsureState(building: any): any?
	local data = DataHandler:GetData(building.Player)

	return data and data.Session[building.Definition.StateField]
end

function DisplaySlot.BuildConfig(building: any): any
	local display = building.State
	local index = building.Index

	local function HasDish(): boolean
		return display[index] ~= nil
	end

	local function IsEmpty(): boolean
		return display[index] == nil
	end

	return {
		initialState = if display[index] then "Filled" else "Empty",
		params = { Now = 0 },
		states = {
			Empty = {},
			Filled = {},
		},
		transitions = {
			{ from = "Empty", to = "Filled", condition = HasDish },
			{ from = "Filled", to = "Empty", condition = IsEmpty },
		},
	}
end

function DisplaySlot.Place(building: any): boolean
	local display = building.State
	local held = InventoryHandler:Peek(building.Player)
	if not held or (held.Kind ~= "Dish" and held.Kind ~= "Leftover") then
		Bus.Progress.ActionFailed:FireClient(building.Player, "nothing_to_place")
		return false
	end
	local data = DataHandler:GetData(building.Player)
	if not data then
		return false
	end
	local leftovers = data.Session.DisplayLeftovers
	local heldLeftover = held.Kind == "Leftover"
	local current = display[building.Index]
	if current then
		local previous = InventoryHandler:ExchangeDish(
			building.Player,
			current,
			PickupOrigin.ForBuilding(building),
			leftovers[building.Index]
		)
		if not previous then
			return false
		end
		SetLeftover(leftovers, building.Index, heldLeftover)
		display[building.Index] = previous
		return true
	end

	InventoryHandler:Pop(building.Player)
	SetLeftover(leftovers, building.Index, heldLeftover)
	display[building.Index] = held.Id

	building:SetState("Filled")

	return true
end

function DisplaySlot.Take(building: any): boolean
	local display = building.State
	local recipeId = display[building.Index]
	if not recipeId then
		return false
	end

	local data = DataHandler:GetData(building.Player)
	if not data then
		return false
	end
	local leftovers = data.Session.DisplayLeftovers
	local kind: GameTypes.ItemKind = if leftovers[building.Index] then "Leftover" else "Dish"
	if
		not InventoryHandler:Push(building.Player, { Kind = kind, Id = recipeId }, PickupOrigin.ForBuilding(building))
	then
		Bus.Progress.ActionFailed:FireClient(building.Player, "hands_full")
		return false
	end

	display[building.Index] = nil
	leftovers[building.Index] = nil

	building:SetState("Empty")

	return true
end

return DisplaySlot
