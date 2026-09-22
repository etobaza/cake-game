--!strict
-- Publishes only the carried item's appearance for other players. Inventory remains server-owned.
-- A single attribute changes atomically, so clients never combine a new kind with an old recipe.

--[[ Services ]]--
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.FoodPresentation)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local FoodReplicationHandler = { dependencies = { "DataHandler", "InventoryHandler" } }

--[[ Handling ]]--
function FoodReplicationHandler.OnInit(self: FoodReplicationHandler): ()
	self.Players = {}
	self.Janitor = Janitor.new()
end

function FoodReplicationHandler.Publish(_self: FoodReplicationHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local item = data.Session.Hands[1]
	local origin = item and item.PickupOrigin
	local value = if item
		then HttpService:JSONEncode({
			Kind = item.Kind,
			Id = item.Id,
			PickupAt = item.PickupAt,
			PickupOrigin = if origin then { origin.X, origin.Y, origin.Z } else nil,
		})
		else ""
	if player:GetAttribute(Config.HandAttribute) ~= value then
		player:SetAttribute(Config.HandAttribute, value)
	end
end

function FoodReplicationHandler.Attach(self: FoodReplicationHandler, player: Player): ()
	if self.Players[player] then
		return
	end
	local connection = DataHandler:SubscribeToPath(player, { "Hands" }, function()
		self:Publish(player)
	end, "Session", true)
	if not connection then
		return
	end
	local janitor = Janitor.new()
	janitor:Add(connection, "Disconnect")
	self.Players[player] = janitor
	self:Publish(player)
end

function FoodReplicationHandler.OnStart(self: FoodReplicationHandler): ()
	self.Janitor:Add(
		DataHandler.PlayerReady:Connect(function(player: Player)
			self:Attach(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player)
			local janitor = self.Players[player]
			if janitor then
				janitor:Destroy()
			end
			self.Players[player] = nil
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		self:Attach(player)
	end
end

function FoodReplicationHandler.Destroy(self: FoodReplicationHandler): ()
	for player, janitor in self.Players do
		janitor:Destroy()
		player:SetAttribute(Config.HandAttribute, nil)
	end
	self.Players = {}
	self.Janitor:Destroy()
end

export type FoodReplicationHandler = typeof(FoodReplicationHandler) & { Players: { [Player]: any }, Janitor: any }
return FoodReplicationHandler :: FoodReplicationHandler
