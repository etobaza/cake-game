--!strict
-- Assistant: like Lemon Cake's BP_Assistant it works every job itself, one action per interval during
-- the shift, taking the first that has work: the kitchen window, coffee, a dirty table, the display.

--[[ Services ]]--
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local BuildingHandler = require(ServerScriptService.Handlers.BuildingHandler)
local CustomerHandler = require(ServerScriptService.Handlers.CustomerHandler)
local DayCycleHandler = require(ServerScriptService.Handlers.DayCycleHandler)
local DisplayHandler = require(ServerScriptService.Handlers.DisplayHandler)
local TableHandler = require(ServerScriptService.Handlers.TableHandler)
local TickHandler = require(ServerScriptService.Handlers.TickHandler)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Constants ]]--
local ASSISTANT_INTERVAL = 8
local COFFEE_RECIPE = "coffee"

--[[ Tables ]]--
local AssistantHandler = {
	dependencies = {
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

	Players.PlayerRemoving:Connect(function(player: Player)
		self.NextActionAt[player] = nil
	end)
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
			local _ = self:CarryFromWindow(player)
				or self:ServeCoffee(player)
				or self:CleanTable(player)
				or self:CarryToDisplay(player)
		end
	end
end

function AssistantHandler.CleanTable(_self: AssistantHandler, player: Player): boolean
	local tableId = TableHandler:FindDirty(player)
	return tableId ~= nil and TableHandler:Clean(player, tableId)
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

-- Moves the kitchen window's pastry to a free display. With no free display it stays on the window.
function AssistantHandler.CarryFromWindow(_self: AssistantHandler, player: Player): boolean
	if not DisplayHandler:HasFreeSlot(player) then
		return false
	end

	local recipeId, leftover = DisplayHandler:TakeWindowDish(player)
	if not recipeId then
		return false
	end

	return DisplayHandler:PlaceDish(player, recipeId, leftover)
end

export type AssistantHandler = typeof(AssistantHandler) & {
	NextActionAt: { [Player]: number },
}

return AssistantHandler :: AssistantHandler
