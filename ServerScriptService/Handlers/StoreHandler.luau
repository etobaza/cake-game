--!strict
-- What a Robux purchase actually gives, and which passes a player owns.
--
-- PurchaseHandler owns the Marketplace plumbing -- prompts, receipts, deduplication -- and says
-- "this player completed this product". This handler is the other half: it turns that into coins in
-- the wallet, and it keeps Cloud.Passes in step with what Roblox says the player owns.
--
-- Nothing reads a pass through this handler. The effects live where the numbers already live: the
-- coin multiplier inside EconomyHandler.AddCash, the stat bonus inside UpgradeHandler.GetStat, both
-- computed from Cloud.Passes and the product registry. That keeps this file a writer, not a hub.

--[[ Services ]]--
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local LoggerUtil = require(_Libs.Logger)
local Products = require(_Configs.Registries.Products)
local PurchaseHandler = require(ServerScriptService.Handlers.PurchaseHandler)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "StoreHandler" })

--[[ Tables ]]--
local StoreHandler = {
	dependencies = { "DataHandler", "EconomyHandler", "PurchaseHandler", "UpgradeHandler" },
	priority = 60,
}

--[[ Private Functions ]]--
-- Every product that is owned once and stays owned: gamepasses, and the permanent dev products.
local function LastingProducts(): { Products.ProductEntry }
	return Products:Query()
		:Where(function(entry: Products.ProductEntry): boolean
			return entry.productType == "gamepass" or entry.productType == "permanent_devproduct"
		end)
		:ToArray()
end

-- An unset id means the product has not been created on the Dashboard yet; asking Roblox about it
-- would only throw.
local function IsForSale(entry: Products.ProductEntry): boolean
	return entry.productId > 0
end

--[[ Handling ]]--
function StoreHandler.OnStart(self: StoreHandler): ()
	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number)
		self:Grant(player, productId)
	end)

	DataHandler.PlayerReady:Connect(function(player: Player)
		task.spawn(function()
			self:SyncPasses(player)
		end)
	end)

	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			task.spawn(function()
				self:SyncPasses(player)
			end)
		end
	end
end

--- Rewrites Cloud.Passes from what Roblox and the receipt cache say. Yields on the web call, so it
--- is always run in its own thread.
function StoreHandler.SyncPasses(_self: StoreHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local owned = data.Cloud.Passes

	for _, entry in LastingProducts() do
		if not IsForSale(entry) then
			continue
		end

		local has = false

		if entry.productType == "gamepass" then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.productId)
			end)
			has = ok and result == true

			if not ok then
				Logger:Warn(`Could not read ownership of {entry.id} for {player.Name}: {result}`)
				continue
			end
		else
			has = data.Cloud._productCache[`owned_{entry.id}`] == true
		end

		if has and not DataList.Contains(owned, entry.id) then
			DataList.Append(owned, entry.id)
		end
	end

	-- A pass can change what a stat is worth, and the cache in front of that stat is not ours.
	UpgradeHandler:Invalidate(player)
end

--- Hands over what the product promised. Everything is described in the registry, so a new product
--- is a row there and nothing here.
function StoreHandler.Grant(self: StoreHandler, player: Player, productId: number): ()
	local entry = Products:GetByProductId(productId)
	local meta = entry and entry.meta
	if not entry or not meta then
		return
	end

	if meta.grant == "Cash" then
		EconomyHandler:AddCash(player, meta.amount)
		Logger:Info(`{player.Name} bought {entry.id} for {meta.amount} coins`)
		return
	end

	-- A pass changes nothing by itself; it changes what the sums read. Re-reading ownership is the
	-- whole grant.
	if meta.grant == "CashMultiplier" or meta.grant == "Stat" then
		task.spawn(function()
			self:SyncPasses(player)
		end)

		Logger:Info(`{player.Name} bought the {entry.id} pass`)
	end
end

export type StoreHandler = typeof(StoreHandler)

return StoreHandler :: StoreHandler
