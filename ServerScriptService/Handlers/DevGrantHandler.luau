--!strict
-- Studio-only QA: grants a Robux product without a purchase, so passes and boosts can be tested in a
-- Play session. Set the player's `DevGrant` attribute to a Registries/Products id on the server (the
-- Studio command bar or MCP); the attribute is cleared once handled. Use it with the DataHandler
-- `AdminTestMockData` attribute so nothing reaches a real profile. Does nothing outside Studio.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local CashBoostHandler = require(ServerScriptService.Handlers.CashBoostHandler)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(ReplicatedStorage.Shared.DataList)
local LimitedHandler = require(ServerScriptService.Handlers.LimitedHandler)
local OfferHandler = require(ServerScriptService.Handlers.OfferHandler)
local Products = require(ReplicatedStorage.Shared.Configs.Registries.Products)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Constants ]]--
local ATTRIBUTE = "DevGrant"

--[[ Tables ]]--
local DevGrantHandler = {
	dependencies = { "DataHandler", "UpgradeHandler", "CashBoostHandler", "LimitedHandler", "OfferHandler" },
}

--[[ Handling ]]--
function DevGrantHandler.OnStart(self: DevGrantHandler): ()
	if not RunService:IsStudio() then
		return
	end

	local function watch(player: Player): ()
		player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			local entryId = player:GetAttribute(ATTRIBUTE)
			if typeof(entryId) == "string" and entryId ~= "" then
				player:SetAttribute(ATTRIBUTE, nil)
				self:Grant(player, entryId)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function DevGrantHandler.Grant(_self: DevGrantHandler, player: Player, entryId: string): ()
	local entry = Products:Get(entryId)
	local data = DataHandler:GetData(player)
	local meta = entry and entry.meta
	if not entry or not meta or not data then
		print(`[DevGrantHandler] Unknown product or no data: {entryId}`)
		return
	end

	if meta.grant == "CashBoost" then
		CashBoostHandler:Add(player, meta.amount)
	elseif meta.grant == "Limited" then
		-- As a slot receipt with no prompt behind it: the drop on sale, while copies remain.
		LimitedHandler:GrantSlot(player)
	elseif meta.offer then
		-- As a receipt for that offer at this moment: it pays its fallback when nothing applies.
		OfferHandler:Grant(player, entry)
	elseif entry.productType == "gamepass" and not DataList.Contains(data.Cloud.Passes, entry.id) then
		DataList.Append(data.Cloud.Passes, entry.id)
		UpgradeHandler:Invalidate(player)
	end
	print(`[DevGrantHandler] Granted {entryId} to {player.Name}`)
end

export type DevGrantHandler = typeof(DevGrantHandler)

return DevGrantHandler :: DevGrantHandler
