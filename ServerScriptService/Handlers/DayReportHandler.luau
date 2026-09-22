--!strict
-- Observes completed station transitions and accepted full orders for the daily report.
-- DayCycleHandler owns the counters, reset and frozen Summary snapshot.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Handlers = ServerScriptService.Handlers
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local BuildingHandler = require(_Handlers.BuildingHandler)
local CustomerHandler = require(_Handlers.CustomerHandler)
local DayCycleHandler = require(_Handlers.DayCycleHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(_Shared.Configs.Registries.Recipes)

--[[ Constants ]]--
local ORDER_RESULT: { [string]: string } = { Happy = "Perfect", Singing = "Good", Angry = "Late" }

--[[ Tables ]]--
local DayReportHandler = {
	-- Both event sources and the day counter owner must be initialized first.
	dependencies = { "BuildingHandler", "CustomerHandler", "DayCycleHandler" },
}

--[[ Handling ]]--
function DayReportHandler.OnStart(self: DayReportHandler): ()
	self.Janitor = Janitor.new()
	self.Janitor:Add(
		BuildingHandler.StateChanged:Connect(
			function(player: Player, building: any, state: string, previous: string?): ()
				if building.Definition.Class ~= "Station" then
					return
				end
				if state == "Burnt" and previous == "Ready" then
					DayCycleHandler:RecordStat(player, "Burned")
					return
				end
				if state ~= "Ready" or (previous ~= "Mixing" and previous ~= "Cooking") then
					return
				end
				local recipe = Recipes:Get(building.State.RecipeId)
				if recipe and (not building.Definition.Mixes or recipe.cookSeconds == 0) then
					DayCycleHandler:RecordStat(player, "Baked")
				end
			end
		),
		"Disconnect"
	)
	self.Janitor:Add(
		CustomerHandler.CustomerEating:Connect(
			function(player: Player, _customerId: string, _recipeId: string, reaction: string): ()
				local key = ORDER_RESULT[reaction]
				if key then
					DayCycleHandler:RecordStat(player, key)
				end
			end
		),
		"Disconnect"
	)
	-- BP_Client.BuyCounterFood records a good order without entering the dining/eating flow.
	self.Janitor:Add(
		CustomerHandler.CustomerPurchased:Connect(function(player: Player)
			DayCycleHandler:RecordStat(player, "Good")
		end),
		"Disconnect"
	)
end

function DayReportHandler.Destroy(self: DayReportHandler): ()
	self.Janitor:Destroy()
end

export type DayReportHandler = typeof(DayReportHandler) & { Janitor: any }
return DayReportHandler :: DayReportHandler
