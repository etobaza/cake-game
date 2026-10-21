--!strict
-- Assistant: like Lemon Cake's BP_Assistant it works every job itself, one action per interval during
-- the shift, taking the first that has work: the kitchen window, coffee, a dirty table, the display.
-- The Hire a Helper pass unlocks it and halves the interval (Configs/Workers); WorkerHandler gives it
-- a body that walks to each job through the Acted signal.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local BuildingHandler = require(ServerScriptService.Handlers.BuildingHandler)
local CustomerHandler = require(ServerScriptService.Handlers.CustomerHandler)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(ReplicatedStorage.Shared.DataList)
local DayCycleHandler = require(ServerScriptService.Handlers.DayCycleHandler)
local DisplayHandler = require(ServerScriptService.Handlers.DisplayHandler)
local Signal = require(ReplicatedStorage.Shared.Libs.Signal)
local TableHandler = require(ServerScriptService.Handlers.TableHandler)
local TickHandler = require(ServerScriptService.Handlers.TickHandler)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)
local WorkersConfig = require(ReplicatedStorage.Shared.Configs.Workers)

--[[ Constants ]]--
local ASSISTANT_INTERVAL = 8
local COFFEE_RECIPE = "coffee"

--[[ Tables ]]--
local AssistantHandler = {
	dependencies = {
		"DataHandler",
		"TickHandler",
		"DayCycleHandler",
		"TableHandler",
		"DisplayHandler",
		"BuildingHandler",
		"CustomerHandler",
		"UpgradeHandler",
	},
	priority = 30,
}

-- Fired after a job is done: the player and the world position the job happened at.
AssistantHandler.Acted = Signal() :: Signal.Signal<Player, Vector3>

--[[ Private Functions ]]--
-- Where a building of this kind stands in the player's bakery, for the worker's walk.
local function KindPosition(player: Player, kind: string): Vector3?
	for _, building in BuildingHandler:GetBuildings(player) do
		if building.Kind == kind then
			return building.Part.Position
		end
	end
	return nil
end

local function OwnsHelperPass(player: Player): boolean
	local data = DataHandler:GetData(player)
	return data ~= nil and DataList.Contains(data.Cloud.Passes, WorkersConfig.HelperPass)
end

--[[ Handling ]]--
function AssistantHandler.OnInit(self: AssistantHandler): ()
	self.NextActionAt = {}
end

function AssistantHandler.OnStart(self: AssistantHandler): ()
	DayCycleHandler.ShiftStarted:Connect(function(player: Player)
		self.NextActionAt[player] = workspace:GetServerTimeNow() + self:GetInterval(player)
	end)

	TickHandler.Tick:Connect(function()
		self:UpdateAssistants()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.NextActionAt[player] = nil
	end)
end

function AssistantHandler.GetInterval(_self: AssistantHandler, player: Player): number
	return if OwnsHelperPass(player) then ASSISTANT_INTERVAL / WorkersConfig.HelperSpeedup else ASSISTANT_INTERVAL
end

function AssistantHandler.UpdateAssistants(self: AssistantHandler): ()
	local now = workspace:GetServerTimeNow()

	for _, player in Players:GetPlayers() do
		local nextAt = self.NextActionAt[player]
		if not nextAt or now < nextAt then
			continue
		end

		self.NextActionAt[player] = now + self:GetInterval(player)

		if DayCycleHandler:IsShiftActive(player) and UpgradeHandler:HasStat(player, "AssistantSlots") then
			local _ = self:CarryFromWindow(player)
				or self:ServeCoffee(player)
				or self:CleanTable(player)
				or self:CarryToDisplay(player)
		end
	end
end

function AssistantHandler.Report(self: AssistantHandler, player: Player, position: Vector3?): boolean
	if position then
		self.Acted:Fire(player, position)
	end
	return true
end

function AssistantHandler.CleanTable(self: AssistantHandler, player: Player): boolean
	local tableId = TableHandler:FindDirty(player)
	if tableId == nil or not TableHandler:Clean(player, tableId) then
		return false
	end
	local building = BuildingHandler:GetBuilding(player, tableId)
	return self:Report(player, building and building.Part.Position)
end

-- Carries coffee to whoever is waiting for it. The assistant cannot cook, only serve.
function AssistantHandler.ServeCoffee(self: AssistantHandler, player: Player): boolean
	local customerId = CustomerHandler:FindWaitingFor(player, COFFEE_RECIPE)
	if not customerId then
		return false
	end

	if not DisplayHandler:RemoveDish(player, COFFEE_RECIPE) then
		return false
	end

	if not CustomerHandler:ServeDish(player, customerId, COFFEE_RECIPE) then
		return false
	end
	return self:Report(player, KindPosition(player, "Coffee"))
end

-- Moves a finished dish from a station to the display. Free space is checked before taking it off
-- the station, otherwise a full display would simply make the dish vanish.
function AssistantHandler.CarryToDisplay(self: AssistantHandler, player: Player): boolean
	if not DisplayHandler:HasFreeSlot(player) then
		return false
	end

	local recipeId = BuildingHandler:TakeReadyDish(player)
	if not recipeId then
		return false
	end

	if not DisplayHandler:PlaceDish(player, recipeId) then
		return false
	end
	return self:Report(player, KindPosition(player, "Display"))
end

-- Moves the kitchen window's pastry to a free display. With no free display it stays on the window.
function AssistantHandler.CarryFromWindow(self: AssistantHandler, player: Player): boolean
	if not DisplayHandler:HasFreeSlot(player) then
		return false
	end

	local recipeId, leftover = DisplayHandler:TakeWindowDish(player)
	if not recipeId then
		return false
	end

	if not DisplayHandler:PlaceDish(player, recipeId, leftover) then
		return false
	end
	return self:Report(player, KindPosition(player, "Display"))
end

export type AssistantHandler = typeof(AssistantHandler) & {
	NextActionAt: { [Player]: number },
}

return AssistantHandler :: AssistantHandler
