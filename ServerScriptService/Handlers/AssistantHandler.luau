--!strict
-- Assistant: one task picked for the day. During the shift it does one thing per interval.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BuildingHandler = require(ServerScriptService.Handlers.BuildingHandler)
local Bus = require(_Shared.Bus)
local CustomerHandler = require(ServerScriptService.Handlers.CustomerHandler)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DayCycleHandler = require(ServerScriptService.Handlers.DayCycleHandler)
local DisplayHandler = require(ServerScriptService.Handlers.DisplayHandler)
local LoggerUtil = require(_Libs.Logger)
local Sanitize = require(_Shared.Sanitize)
local TableHandler = require(ServerScriptService.Handlers.TableHandler)
local TickHandler = require(ServerScriptService.Handlers.TickHandler)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Constants ]]--
local ASSISTANT_INTERVAL = 8
local COFFEE_RECIPE = "coffee"
local TASKS = { None = true, Tables = true, Coffee = true, Display = true }

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "AssistantHandler" })

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

--[[ Private Functions ]]--
local function GetTask(player: Player): string
	local data = DataHandler:GetData(player)
	return if data then data.Cloud.AssistantTask else "None"
end

--[[ Handling ]]--
function AssistantHandler.OnInit(self: AssistantHandler): ()
	self.NextActionAt = {}
end

function AssistantHandler.OnStart(self: AssistantHandler): ()
	DayCycleHandler.ShiftStarted:Connect(function(player: Player)
		self.NextActionAt[player] = workspace:GetServerTimeNow() + ASSISTANT_INTERVAL
	end)

	TickHandler.Tick:Connect(function()
		self:UpdateAssistants()
	end)

	Bus.Progress.SetAssistantTask.OnServerEvent:Connect(function(player: Player, taskId: any)
		local id = Sanitize.Id(taskId)
		if id then
			self:SetTask(player, id)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.NextActionAt[player] = nil
	end)
end

-- The task is picked while planning tomorrow and holds for that whole day.
function AssistantHandler.SetTask(_self: AssistantHandler, player: Player, taskId: string): boolean
	if not TASKS[taskId] then
		return false
	end

	if not UpgradeHandler:HasStat(player, "AssistantSlots") then
		Bus.Progress.ActionFailed:FireClient(player, "no_assistant")
		return false
	end

	if DayCycleHandler:GetPhase(player) ~= "Summary" then
		Bus.Progress.ActionFailed:FireClient(player, "not_summary_phase")
		return false
	end

	local data = DataHandler:GetData(player)
	if not data then
		return false
	end

	data.Cloud.AssistantTask = taskId
	Logger:Debug(`{player.Name} assigned the assistant to {taskId}`)

	return true
end

function AssistantHandler.UpdateAssistants(self: AssistantHandler): ()
	local now = workspace:GetServerTimeNow()

	for _, player in Players:GetPlayers() do
		local nextAt = self.NextActionAt[player]
		if not nextAt or now < nextAt then
			continue
		end

		self.NextActionAt[player] = now + ASSISTANT_INTERVAL

		if DayCycleHandler:IsShiftActive(player) and UpgradeHandler:HasStat(player, "AssistantSlots") then
			self:DoTask(player, GetTask(player))
		end
	end
end

function AssistantHandler.DoTask(self: AssistantHandler, player: Player, taskId: string): boolean
	if taskId == "Tables" then
		local tableId = TableHandler:FindDirty(player)
		return tableId ~= nil and TableHandler:Clean(player, tableId)
	end

	if taskId == "Coffee" then
		return self:ServeCoffee(player)
	end

	if taskId == "Display" then
		return self:CarryToDisplay(player)
	end

	return false
end

-- Carries coffee to whoever is waiting for it. The assistant cannot cook, only serve.
function AssistantHandler.ServeCoffee(_self: AssistantHandler, player: Player): boolean
	local customerId = CustomerHandler:FindWaitingFor(player, COFFEE_RECIPE)
	if not customerId then
		return false
	end

	if not DisplayHandler:RemoveDish(player, COFFEE_RECIPE) then
		return false
	end

	return CustomerHandler:ServeDish(player, customerId, COFFEE_RECIPE)
end

-- Moves a finished dish from a station to the display. Free space is checked before taking it off
-- the station, otherwise a full display would simply make the dish vanish.
function AssistantHandler.CarryToDisplay(_self: AssistantHandler, player: Player): boolean
	if not DisplayHandler:HasFreeSlot(player) then
		return false
	end

	local recipeId = BuildingHandler:TakeReadyDish(player)
	if not recipeId then
		return false
	end

	return DisplayHandler:PlaceDish(player, recipeId)
end

export type AssistantHandler = typeof(AssistantHandler) & {
	NextActionAt: { [Player]: number },
}

return AssistantHandler :: AssistantHandler
