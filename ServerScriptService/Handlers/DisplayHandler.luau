--!strict
-- The display shelf as the rest of the game sees it: what lies on it and where there is room.
-- A single slot is a building (BuildingHandler/Kinds/DisplaySlot) and owns the player actions;
-- writes made here are picked up by the slot machines on the next tick.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Configs = ReplicatedStorage.Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DayCycleHandler = require(ServerScriptService.Handlers.DayCycleHandler)
local FoodPresentation = require(_Configs.FoodPresentation)
local Recipes = require(_Configs.Registries.Recipes)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Constants ]]--
local DISPLAY_KIND = "Display"

--[[ Tables ]]--
local DisplayHandler = {
	dependencies = { "DataHandler", "UpgradeHandler", "DayCycleHandler" },
	priority = 50,
}

--[[ Private Functions ]]--
local function GetDisplay(player: Player): { [number]: string }?
	local data = DataHandler:GetData(player)
	return data and data.Session.Display
end

local function GetLeftovers(player: Player): { [number]: boolean }?
	local data = DataHandler:GetData(player)
	return data and data.Session.DisplayLeftovers
end

--[[ Handling ]]--
function DisplayHandler.OnStart(self: DisplayHandler): ()
	DayCycleHandler.DayStarted:Connect(function(player: Player)
		self:AgeStock(player)
	end)
end

-- Like BP_Counter.DailyReset: fresh stock becomes half-price leftovers once; frozen food melts.
function DisplayHandler.AgeStock(_self: DisplayHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	for index, recipeId in data.Session.Display do
		if data.Session.DisplayLeftovers[index] then
			continue
		end
		local recipe = Recipes:Get(recipeId)
		if not recipe then
			continue
		end
		if recipe.station == "Freezer" then
			data.Session.Display[index] = nil
		else
			data.Session.DisplayLeftovers[index] = true
		end
	end
end

function DisplayHandler.GetGuestCapacity(_self: DisplayHandler, player: Player): number
	local pedestals = math.clamp(
		UpgradeHandler:GetLevel(player, FoodPresentation.DisplayUpgrade),
		0,
		FoodPresentation.DisplayPedestals
	)
	return pedestals
end

-- Slot 1 and bonus ledges are storage. Purchased window pedestals are slots 2..N+1.
function DisplayHandler.FindStockedSlot(self: DisplayHandler, player: Player): number?
	local display = GetDisplay(player)
	if not display then
		return nil
	end
	for index = 2, self:GetGuestCapacity(player) + 1 do
		if display[index] then
			return index
		end
	end
	return nil
end

-- Recheck the exact visited pedestal: another visitor or the player may have taken its food.
function DisplayHandler.TakeSlot(self: DisplayHandler, player: Player, index: number): (string?, boolean?)
	local display = GetDisplay(player)
	local leftovers = GetLeftovers(player)
	if not display or not leftovers or index < 2 or index > self:GetGuestCapacity(player) + 1 then
		return nil, nil
	end
	local recipeId = display[index]
	local leftover = leftovers[index] == true
	if recipeId then
		display[index] = nil
		leftovers[index] = nil
	end
	return recipeId, leftover
end

function DisplayHandler.GetSlotCount(_self: DisplayHandler, player: Player): number
	local stat = BuildingsConfig.Kinds[DISPLAY_KIND].Stat :: any

	return UpgradeHandler:GetStat(player, stat)
end

function DisplayHandler.HasFreeSlot(self: DisplayHandler, player: Player): boolean
	local display = GetDisplay(player)
	if not display then
		return false
	end

	for slotIndex = 2, self:GetGuestCapacity(player) + 1 do
		if not display[slotIndex] then
			return true
		end
	end

	return false
end

-- Puts a dish into the first free slot past the player's hands: used by the assistant.
function DisplayHandler.PlaceDish(self: DisplayHandler, player: Player, recipeId: string): boolean
	local display = GetDisplay(player)
	local leftovers = GetLeftovers(player)
	if not display or not leftovers then
		return false
	end

	for slotIndex = 2, self:GetGuestCapacity(player) + 1 do
		if not display[slotIndex] then
			leftovers[slotIndex] = nil
			display[slotIndex] = recipeId
			return true
		end
	end

	return false
end

function DisplayHandler.FindDish(_self: DisplayHandler, player: Player, recipeId: string): number?
	local display = GetDisplay(player)
	local leftovers = GetLeftovers(player)
	if not display or not leftovers then
		return nil
	end

	for slotIndex, dishId in display do
		if dishId == recipeId and not leftovers[slotIndex] then
			return slotIndex
		end
	end

	return nil
end

-- The assistant takes fresh matching stock; window shoppers use TakeSlot instead.
function DisplayHandler.RemoveDish(self: DisplayHandler, player: Player, recipeId: string): boolean
	local display = GetDisplay(player)
	local slotIndex = self:FindDish(player, recipeId)
	if not display or not slotIndex then
		return false
	end

	display[slotIndex] = nil

	return true
end

-- Fresh stock available for recipe-based consumers.
function DisplayHandler.GetDishes(_self: DisplayHandler, player: Player): { string }
	local display = GetDisplay(player)
	local leftovers = GetLeftovers(player)
	local dishes: { string } = {}

	if not display or not leftovers then
		return dishes
	end

	for index, dishId in display do
		if not leftovers[index] then
			dishes[#dishes + 1] = dishId
		end
	end

	return dishes
end

export type DisplayHandler = typeof(DisplayHandler)

return DisplayHandler :: DisplayHandler
