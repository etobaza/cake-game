--!strict
-- Tables as the rest of the game sees them: reserve a clean seat, release one guest, clean used places.
-- The state of a single table lives in its building (BuildingHandler/Kinds/CafeTable); this is the
-- lookup layer over all of them.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BuildingHandler = require(ServerScriptService.Handlers.BuildingHandler)
local Bus = require(_Shared.Bus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local Sanitize = require(_Shared.Sanitize)
local Signal = require(_Libs.Signal)
local TutorialEvents = require(ServerScriptService.TutorialEvents)

--[[ Constants ]]--
local TABLE_KIND = "Table"

--[[ Tables ]]--
local TableHandler = {
	dependencies = { "BuildingHandler", "DataHandler" },
	priority = 50,
}

-- Fired when a dirty table became clean again: the assistant and the UI watch this.
TableHandler.TableCleaned = Signal() :: Signal.Signal<Player, string>

--[[ Handling ]]--
function TableHandler.OnStart(self: TableHandler): ()
	Bus.Cafe.CleanTable.OnServerEvent:Connect(function(player: Player, value: any)
		local id = Sanitize.Id(value)
		if not id or not BuildingHandler:ValidateRemoteBuilding(player, id, TABLE_KIND) then
			return
		end
		if self:Clean(player, id, true) then
			TutorialEvents.Action:Fire(player, "CleanTable", id)
		end
	end)
end

function TableHandler.FindFree(_self: TableHandler, player: Player): string?
	local best: any = nil
	local bestOccupied = -1
	for _, building in BuildingHandler:GetBuildings(player) do
		if building.Kind ~= TABLE_KIND or not BuildingHandler:Dispatch(player, building.Id, "FindFreeSeat") then
			continue
		end
		local occupied = 0
		for _, seat in building.State.Seats do
			if seat.CustomerId then
				occupied += 1
			end
		end
		-- Fill an already occupied table first; seat reservations count while guests are walking in.
		if occupied > bestOccupied or (occupied == bestOccupied and best and building.Index < best.Index) then
			best, bestOccupied = building, occupied
		end
	end
	return best and best.Id
end

function TableHandler.FindDirty(_self: TableHandler, player: Player): string?
	for _, building in BuildingHandler:GetBuildings(player) do
		if building.Kind == TABLE_KIND and building.State and building.State.Dirty then
			return building.Id
		end
	end
	return nil
end

function TableHandler.Occupy(_self: TableHandler, player: Player, tableId: string, customerId: string): number?
	return BuildingHandler:Dispatch(player, tableId, "Occupy", customerId)
end

function TableHandler.Release(_self: TableHandler, player: Player, tableId: string, customerId: string): ()
	BuildingHandler:Dispatch(player, tableId, "Release", customerId)
end

function TableHandler.CanServe(_self: TableHandler, player: Player, tableId: string, customerId: string): boolean
	if not BuildingHandler:ValidateRemoteBuilding(player, tableId, TABLE_KIND) then
		return false
	end
	return BuildingHandler:Dispatch(player, tableId, "HasCustomer", customerId) == true
end

function TableHandler.ServeMenu(
	_self: TableHandler,
	player: Player,
	tableId: string,
	customerId: string,
	recipeId: string
): ()
	BuildingHandler:Dispatch(player, tableId, "ServeMenu", customerId, recipeId)
end

function TableHandler.TakeOrder(_self: TableHandler, player: Player, tableId: string, customerId: string): ()
	BuildingHandler:Dispatch(player, tableId, "TakeOrder", customerId)
end

function TableHandler.Clean(self: TableHandler, player: Player, tableId: string, manual: boolean?): boolean
	local data = DataHandler:GetData(player)
	local context = data and data.Session.Tutorial
	-- Leave the teaching place for its owner; assistants continue cleaning other places.
	if not manual and context and context.Protected and context.TableId == tableId then
		return false
	end
	if BuildingHandler:Dispatch(player, tableId, "Clean") ~= true then
		return false
	end
	if manual then
		Bus.Player.PlayAction:FireClient(player, "Cleaning")
	end
	self.TableCleaned:Fire(player, tableId)
	return true
end

export type TableHandler = typeof(TableHandler)

return TableHandler :: TableHandler
