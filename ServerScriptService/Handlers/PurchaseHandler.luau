local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Libs.Signal)
local LoggerUtil = require(ReplicatedStorage.Shared.Libs.Logger)
local Products = require(ReplicatedStorage.Shared.Configs.Registries.Products)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local Bus = require(ReplicatedStorage.Shared.Bus)

local Logger = LoggerUtil.new({ name = "PurchaseHandler" })

export type PurchasePromise = {
	andThen: (self: PurchasePromise, callback: () -> ()) -> PurchasePromise,
	catch: (self: PurchasePromise, callback: (err: string) -> ()) -> PurchasePromise,
	finally: (self: PurchasePromise, callback: () -> ()) -> PurchasePromise,
}

local PurchaseHandler = {
	dependencies = { "DataHandler" },
}

-- Signal fired when any purchase completes successfully
PurchaseHandler.PurchaseCompleted = Signal() :: Signal.Signal<Player, number, boolean> -- player, productId, isGift

-- Pending gifts: [sender.UserId] = recipient.UserId
local pendingGifts: { [number]: number } = {}

-- Pending purchases for Promise API: [player.UserId_productId] = {resolve, reject}
local pendingPromises: { [string]: { resolve: () -> (), reject: (string) -> () } } = {}

-- Processed receipts for deduplication (in-memory cache, also stored in CloudData._productCache)
local processedReceipts: { [string]: boolean } = {}

-- Runs the matching callback and then `finally`; `err` nil means the purchase went through.
local function settlePromise(promise: any, err: string?)
	if err == nil then
		if promise._resolveCallback then
			promise._resolveCallback()
		end
	elseif promise._rejectCallback then
		promise._rejectCallback(err)
	end

	if promise._finallyCallback then
		promise._finallyCallback()
	end
end

local function createPurchasePromise(key: string): PurchasePromise
	local promise = {
		_key = key,
		_resolveCallback = nil,
		_rejectCallback = nil,
		_finallyCallback = nil,
	}

	function promise:andThen(callback: () -> ())
		promise._resolveCallback = callback
		return promise
	end

	function promise:catch(callback: (err: string) -> ())
		promise._rejectCallback = callback
		return promise
	end

	function promise:finally(callback: () -> ())
		promise._finallyCallback = callback
		return promise
	end

	pendingPromises[key] = {
		resolve = function()
			settlePromise(promise, nil)
		end,
		reject = function(err: string)
			settlePromise(promise, err)
		end,
	}

	return promise
end

-- Reject on the next frame: the caller still has to attach :catch to the promise we return.
local function rejectLater(key: string, reason: string)
	task.defer(function()
		local pending = pendingPromises[key]
		if not pending then
			return
		end

		pending.reject(reason)
		pendingPromises[key] = nil
	end)
end

local function resolvePromise(player: Player, productId: number)
	local key = `{player.UserId}_{productId}`
	local promiseData = pendingPromises[key]
	if promiseData then
		promiseData.resolve()
		pendingPromises[key] = nil
	end
end

local function isReceiptProcessed(player: Player?, receiptId: string): boolean
	if processedReceipts[receiptId] then
		return true
	end

	-- Fallback to durable cache (covers memory miss / load race).
	if player then
		local data = DataHandler:GetData(player)
		if data and data.Cloud._productCache and data.Cloud._productCache[receiptId] then
			processedReceipts[receiptId] = true
			return true
		end
	end

	return false
end

local function markReceiptProcessed(player: Player, receiptId: string)
	processedReceipts[receiptId] = true

	local data = DataHandler:GetData(player)
	if data then
		if data.Cloud._productCache == nil then
			data.Cloud._productCache = {}
		end
		data.Cloud._productCache[receiptId] = true
	end
end

local function loadProcessedReceipts(player: Player)
	local data = DataHandler:GetData(player)
	if data and data.Cloud._productCache then
		for receiptId, _ in pairs(data.Cloud._productCache) do
			processedReceipts[receiptId] = true
		end
	end
end

local function trackRobuxSpent(player: Player, spent: number)
	if spent <= 0 then
		return
	end

	local data = DataHandler:GetData(player)
	if not data or not data.Cloud then
		return
	end

	-- Do not invent a full Stats schema; only write when present, or create the one field we own.
	local stats = data.Cloud.Stats
	if stats == nil then
		data.Cloud.Stats = { RobuxSpent = spent }
		return
	end

	stats.RobuxSpent = (stats.RobuxSpent or 0) + spent
end

-- Grant after durable receipt/ownership writes. Side effects (signals/client) are last.
local function grantProduct(player: Player, productId: number, isGift: boolean)
	PurchaseHandler.PurchaseCompleted:Fire(player, productId, isGift)
	resolvePromise(player, productId)
	Bus.Purchase.Completed:FireClient(player, productId, isGift)
end

-- Permanent dev products are owned once; ownership lives in the durable product cache.
local function ownsPermanent(player: Player, product: any): boolean
	local data = DataHandler:GetData(player)
	if not data or not data.Cloud._productCache then
		return false
	end

	return data.Cloud._productCache[`owned_{product.id}`] == true
end

-- Gift purchases arrive under the gift id; the recipient was pinned when the prompt opened.
local function takeGiftRecipient(playerId: number): Player?
	local recipientId = pendingGifts[playerId]
	if not recipientId then
		return nil
	end

	local recipient = Players:GetPlayerByUserId(recipientId)
	if not recipient then
		return nil
	end

	pendingGifts[playerId] = nil
	return recipient
end

--[[
	Phase 1 of ProcessReceipt: resolve the product and write durable data.
	Runs inside pcall — a failure here may safely retry on the next receipt callback.
]]
local function resolveReceipt(player: Player, receiptInfo: any): any
	local productId = receiptInfo.ProductId
	local product = Products:GetByProductId(productId)
	local recipient = player
	local isGift = false

	local giftProduct = if product then nil else Products:GetByGiftId(productId)
	if giftProduct then
		local giftRecipient = takeGiftRecipient(receiptInfo.PlayerId)
		if not giftRecipient then
			return { decision = Enum.ProductPurchaseDecision.NotProcessedYet }
		end

		product = giftProduct
		recipient = giftRecipient
		isGift = true
	end

	local grantProductId = if product then product.productId else productId

	if product and product.productType == "permanent_devproduct" then
		local data = DataHandler:GetData(recipient)
		if not data then
			return { decision = Enum.ProductPurchaseDecision.NotProcessedYet }
		end

		if data.Cloud._productCache == nil then
			data.Cloud._productCache = {}
		end

		local ownedKey = `owned_{product.id}`
		if data.Cloud._productCache[ownedKey] then
			return { decision = Enum.ProductPurchaseDecision.PurchaseGranted, alreadyOwned = true }
		end

		data.Cloud._productCache[ownedKey] = true
	end

	trackRobuxSpent(player, receiptInfo.CurrencySpent or 0)

	return {
		decision = Enum.ProductPurchaseDecision.PurchaseGranted,
		recipient = recipient,
		grantProductId = grantProductId,
		isGift = isGift,
	}
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local receiptId = receiptInfo.PurchaseId

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if isReceiptProcessed(player, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local resolveOk, resolved = pcall(resolveReceipt, player, receiptInfo)
	if not resolveOk then
		Logger:Error(`ProcessReceipt resolve failed for {receiptId}: {resolved}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if resolved.decision == Enum.ProductPurchaseDecision.NotProcessedYet then
		return resolved.decision
	end

	-- Phase 2: persist receipt before notifications. Once marked, always Grant.
	markReceiptProcessed(player, receiptId)

	if resolved.alreadyOwned then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Phase 3: side effects. Failures must not trigger Roblox retry (would double-fire).
	local grantOk, grantErr = pcall(grantProduct, resolved.recipient, resolved.grantProductId, resolved.isGift)
	if not grantOk then
		Logger:Error(`ProcessReceipt grant notify failed for {receiptId}: {grantErr}`)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PurchaseHandler.OnInit(_self: PurchaseHandler)
	MarketplaceService.ProcessReceipt = processReceipt

	for _, player in Players:GetPlayers() do
		loadProcessedReceipts(player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		loadProcessedReceipts(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for key, _ in pairs(pendingPromises) do
			if not string.find(key, `{player.UserId}_`, 1, true) then
				continue
			end

			pendingPromises[key] = nil
		end
		pendingGifts[player.UserId] = nil
	end)
end

function PurchaseHandler.PurchaseProduct(_self: PurchaseHandler, player: Player, productId: number): PurchasePromise
	local key = `{player.UserId}_{productId}`
	local promise = createPurchasePromise(key)

	local product = Products:GetByProductId(productId)
	if not product then
		MarketplaceService:PromptProductPurchase(player, productId)
		return promise
	end

	if product.productType == "gamepass" then
		MarketplaceService:PromptGamePassPurchase(player, productId)
		return promise
	end

	if product.productType == "permanent_devproduct" and ownsPermanent(player, product) then
		rejectLater(key, "Already owned")
		return promise
	end

	MarketplaceService:PromptProductPurchase(player, productId)
	return promise
end

function PurchaseHandler.GiftProduct(
	_self: PurchaseHandler,
	sender: Player,
	recipient: Player,
	productId: number
): PurchasePromise
	local product = Products:GetByProductId(productId)
	if not product then
		local key = `{sender.UserId}_{productId}`
		local promise = createPurchasePromise(key)
		rejectLater(key, "Product not found")
		return promise
	end

	if not product.giftId then
		local key = `{sender.UserId}_{productId}`
		local promise = createPurchasePromise(key)
		rejectLater(key, "This product cannot be gifted")
		return promise
	end

	pendingGifts[sender.UserId] = recipient.UserId

	local key = `{sender.UserId}_{product.productId}`
	local promise = createPurchasePromise(key)

	MarketplaceService:PromptProductPurchase(sender, product.giftId)
	return promise
end

function PurchaseHandler.OwnsProduct(_self: PurchaseHandler, player: Player, productId: number): boolean
	local product = Products:GetByProductId(productId)
	if not product then
		return false
	end

	if product.productType == "gamepass" then
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, productId)
	end

	if product.productType == "permanent_devproduct" then
		return ownsPermanent(player, product)
	end

	return false
end

function PurchaseHandler.GetProductById(_self: PurchaseHandler, productId: number)
	return Products:GetByProductId(productId)
end

function PurchaseHandler.OnStart(self: PurchaseHandler)
	Bus.Purchase.RequestPurchase.OnServerEvent:Connect(function(player: Player, productId: number)
		self:PurchaseProduct(player, productId)
	end)

	Bus.Purchase.RequestGift.OnServerEvent:Connect(function(sender: Player, productId: number, recipientUserId: number)
		local recipient = Players:GetPlayerByUserId(recipientUserId)
		if not recipient then
			Bus.Purchase.Failed:FireClient(sender, productId, "Recipient not found")
			return
		end

		self:GiftProduct(sender, recipient, productId)
	end)
end

export type PurchaseHandler = typeof(PurchaseHandler)
return PurchaseHandler :: PurchaseHandler
