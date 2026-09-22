--!strict
-- Cmdr's Admin gate checks access; the registry prices the budget and EconomyHandler grants coins.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local Upgrades = require(ReplicatedStorage.Shared.Configs.Registries.Upgrades)

--[[ Handling ]]--
return function(context: any, player: Player?): string
	local target = player or context.Executor
	if not target or target.Parent ~= Players then
		return "Player is no longer in this server."
	end
	local data = DataHandler:GetData(target)
	if not data then
		return "Player data is not ready."
	end
	if data.Cloud.ProgressResetPending then
		return "Rejoin to finish the pending progress reset first."
	end

	local budget = Upgrades:GetRemainingCost(data.Cloud.Base.Upgrades)
	local cash = EconomyHandler:GetCash(target)
	if cash >= budget then
		return `{target.Name} already has enough coins for all remaining upgrades.`
	end
	EconomyHandler:AddCash(target, budget - cash)
	return `{target.Name} now has {EconomyHandler:GetCash(target)} coins. Remaining upgrades cost {budget}.`
end
