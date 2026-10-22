--!strict
-- Limited items: the drop on sale, shared stock, buyer serials, the showcase in every bakery and the
-- owner's oven skin.
--
-- Every drop is sold through one repeatable developer product (Configs/Limited.SlotProduct).
-- PurchaseHandler owns the receipt; when the slot is bought this handler decides which item it was
-- (the one the buyer was prompted for, recorded in Cloud.LimitedPending, else the drop on sale while
-- copies remain) and
-- grants it: Cloud.Limited[item] marks ownership and the item's Products row joins Cloud.Passes, so
-- its bonus is read like a pass's. Owned items stay owned after their window ends.
--
-- The stock is one DataStore counter per item, read on start and every Config.RefreshSeconds, and
-- bumped by UpdateAsync when a copy is granted, so the bump is the buyer's serial. Copies are checked
-- before the prompt but not reserved; a sale reaching the counter after the last copy is still
-- granted (the receipt cannot be refused) and logged. Studio uses its own store and topic.

--[[ Services ]]--
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local BaseHandler = require(_Handlers.BaseHandler)
local Bus = require(_Shared.Bus)
local Config = require(_Configs.Limited)
local DataHandler = require(_Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local LoggerUtil = require(_Libs.Logger)
local Products = require(_Configs.Registries.Products)
local PurchaseHandler = require(_Handlers.PurchaseHandler)
local UpgradeHandler = require(_Handlers.UpgradeHandler)
local World = require(_Shared.World)

--[[ Constants ]]--
local ENTRANCE_ANCHOR = "Entrance"
local MAX_BUYER_NAME = 40
local IS_STUDIO = RunService:IsStudio()
local TOPIC = if IS_STUDIO then Config.StudioTopic else Config.Topic

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "LimitedHandler" })

--[[ Types ]]--
type ItemState = {
	Id: string,
	Config: Config.Item,
	Entry: Products.ProductEntry,
	Sold: number,
}

-- One oven part wearing a limited surface, and the authored one to put back.
type SkinnedPart = {
	Part: MeshPart,
	Original: SurfaceAppearance,
	Golden: SurfaceAppearance,
}

--[[ Tables ]]--
local LimitedHandler = {
	dependencies = { "DataHandler", "BaseHandler", "PurchaseHandler", "UpgradeHandler" },
}

--[[ Private Functions ]]--
local function now(): number
	return workspace:GetServerTimeNow()
end

local function resolvePath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function ownedTable(player: Player): { [string]: number }?
	local data = DataHandler:GetData(player)
	return data and data.Cloud.Limited
end

local function owns(player: Player, itemId: string): boolean
	local owned = ownedTable(player)
	return owned ~= nil and owned[itemId] ~= nil
end

-- The copy number, or nil while it is still being assigned (stored as 0).
local function serialOf(player: Player, itemId: string): number?
	local owned = ownedTable(player)
	local serial = owned and owned[itemId]
	return if typeof(serial) == "number" and serial > 0 then serial else nil
end

--[[ Handling ]]--
function LimitedHandler.OnInit(self: LimitedHandler): ()
	self.Items = {}
	self.Skins = {}
	self.LastBuy = {}
	self.PendingAt = {}
	self.Showcases = {}
	self.ShownItem = nil
	self.Slot = Products:Get(Config.SlotProduct)
	self.Store = DataStoreService:GetDataStore(if IS_STUDIO then Config.StudioStoreName else Config.StoreName)

	if not self.Slot then
		Logger:Warn(`Limited slot product {Config.SlotProduct} is missing from the registry`)
	end

	-- Created up front: the client waits for this folder before it binds showcases, even when no
	-- drop is displayed yet.
	local folder = workspace:FindFirstChild(Config.ShowcaseFolder) or Instance.new("Folder")
	folder.Name = Config.ShowcaseFolder
	folder.Parent = workspace

	for itemId, item in Config.Items do
		local entry = Products:Get(item.Entry)
		if not entry then
			Logger:Warn(`Limited item {itemId} names unknown product {item.Entry}`)
			continue
		end
		self.Items[itemId] = { Id = itemId, Config = item, Entry = entry, Sold = 0 }
	end
end

function LimitedHandler.OnStart(self: LimitedHandler): ()
	Bus.Limited.Buy.OnServerInvoke = function(player: Player, itemId: string): string
		return self:Buy(player, itemId)
	end

	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number)
		local slot = self.Slot
		if slot and slot.productId > 0 and productId == slot.productId then
			self:GrantSlot(player)
		end
	end)

	-- A dismissed prompt bought nothing, so its pending item must not be granted by a later receipt.
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, isPurchased: boolean)
			local slot = self.Slot
			local player = Players:GetPlayerByUserId(userId)
			if isPurchased or not player or not slot or productId ~= slot.productId then
				return
			end
			local data = DataHandler:GetData(player)
			if data then
				data.Cloud.LimitedPending = ""
			end
			self.PendingAt[player] = nil
		end
	)

	-- Puts every owned item's row back in Passes and numbers a copy that has no serial yet (bought
	-- while the counter was unreachable, or granted from a receipt on join).
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:RestoreOwned(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			self:RestoreOwned(player)
		end
	end

	BaseHandler.BaseReady:Connect(function(player: Player)
		self:ApplySkinFor(player)
	end)
	BaseHandler.BaseRemoving:Connect(function(_player: Player, bakery: Folder)
		self:RemoveSkin(bakery)
	end)
	for _, player in Players:GetPlayers() do
		self:ApplySkinFor(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		self.LastBuy[player] = nil
		self.PendingAt[player] = nil
	end)

	-- The refresh loop draws the showcases first; it waits for the bakeries, so it stays off OnStart.
	task.spawn(function()
		self:Subscribe()
	end)
	task.spawn(function()
		while true do
			self:Refresh()
			self:UpdateShowcases()
			task.wait(Config.RefreshSeconds)
		end
	end)
end

--- The item on sale right now.
function LimitedHandler.ActiveItem(self: LimitedHandler): (ItemState?, Config.Drop?)
	local drop = Config.GetActiveDrop(now())
	return if drop then self.Items[drop.Item] else nil, drop
end

--- Shows the displayed drop's showcase in every bakery and keeps its window attributes current.
--- A new drop replaces the previous showcases.
function LimitedHandler.UpdateShowcases(self: LimitedHandler): ()
	local drop = Config.GetDisplayedDrop(now())
	local item = drop and self.Items[drop.Item]
	local itemId = item and item.Id

	if itemId ~= self.ShownItem then
		for _, showcase in self.Showcases do
			showcase:Destroy()
		end
		table.clear(self.Showcases)
		self.ShownItem = itemId
		if item then
			self:SpawnShowcases(item)
		end
	end

	if not item or not drop then
		return
	end
	local active = Config.GetActiveDrop(now()) == drop
	for _, showcase in self.Showcases do
		showcase:SetAttribute(Config.EndsAtAttribute, drop.EndsAt)
		showcase:SetAttribute(Config.ActiveAttribute, active)
		showcase:SetAttribute(Config.SoldAttribute, item.Sold)
	end
end

--- Clones the item's showcase into every bakery, next to that bakery's Entrance anchor.
function LimitedHandler.SpawnShowcases(self: LimitedHandler, item: ItemState): ()
	local assets = ReplicatedStorage:FindFirstChild(Config.AssetsFolder)
	local template = assets and assets:FindFirstChild(item.Config.Showcase)
	if not template or not template:IsA("Model") then
		Logger:Warn(`Showcase {item.Config.Showcase} is missing from {Config.AssetsFolder}`)
		return
	end

	local folder = workspace:FindFirstChild(Config.ShowcaseFolder) or Instance.new("Folder")
	folder.Name = Config.ShowcaseFolder
	folder.Parent = workspace

	for _, bakery in World.WaitForBakeries():GetChildren() do
		local anchors = bakery:FindFirstChild(BaseConfig.AnchorsFolderName)
		local entrance = anchors and anchors:FindFirstChild(ENTRANCE_ANCHOR)
		if not entrance or not entrance:IsA("BasePart") then
			continue
		end

		local showcase = template:Clone()
		showcase.Name = `{item.Id}_{bakery.Name}`
		-- Streams in and out whole, so the client binds a showcase with every part present.
		showcase.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		showcase:PivotTo(entrance.CFrame * item.Config.Placement)
		showcase:SetAttribute(Config.ItemAttribute, item.Id)
		showcase:SetAttribute(Config.BakeryAttribute, bakery.Name)
		showcase:SetAttribute(Config.StockAttribute, item.Config.Stock)
		showcase:SetAttribute(Config.SoldAttribute, item.Sold)
		showcase.Parent = folder
		table.insert(self.Showcases, showcase)
	end
end

--- Raises the known sold count (never lowers it: servers can read the counter at different times).
function LimitedHandler.SetSold(self: LimitedHandler, item: ItemState, sold: number): ()
	if sold <= item.Sold then
		return
	end
	item.Sold = sold
	if self.ShownItem ~= item.Id then
		return
	end
	for _, showcase in self.Showcases do
		showcase:SetAttribute(Config.SoldAttribute, sold)
	end
end

--- Re-reads the counter of the item on display.
function LimitedHandler.Refresh(self: LimitedHandler): ()
	local drop = Config.GetDisplayedDrop(now())
	local item = drop and self.Items[drop.Item]
	if not item then
		return
	end

	local ok, result = pcall(self.Store.GetAsync, self.Store, item.Id)
	if ok and typeof(result) == "number" then
		self:SetSold(item, result)
	elseif not ok then
		Logger:Warn(`Could not read stock of {item.Id}: {result}`)
	end
end

function LimitedHandler.Subscribe(self: LimitedHandler): ()
	local ok, result = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message: any)
		local payload = message.Data
		if typeof(payload) ~= "table" or payload.j == game.JobId then
			return
		end

		local item = typeof(payload.i) == "string" and self.Items[payload.i] or nil
		local serial = payload.s
		local buyer = payload.b
		if not item or typeof(serial) ~= "number" or serial ~= serial or serial < 1 then
			return
		end
		if typeof(buyer) ~= "string" or #buyer > MAX_BUYER_NAME then
			return
		end

		self:SetSold(item, math.floor(serial))
		Bus.Limited.Sold:Fire(item.Id, buyer, math.floor(serial))
	end)
	if not ok then
		Logger:Warn(`Could not subscribe to {TOPIC}: {result}`)
	end
end

--- Purchase request from the showcase. Returns "" when the prompt opened, else a UIText code.
function LimitedHandler.Buy(self: LimitedHandler, player: Player, itemId: string): string
	local item = self:ActiveItem()
	local slot = self.Slot
	if not item or typeof(itemId) ~= "string" or itemId ~= item.Id then
		return "limited_not_on_sale"
	end

	local clock = os.clock()
	local last = self.LastBuy[player]
	if last and clock - last < Config.BuyCooldown then
		return "limited_cooldown"
	end
	self.LastBuy[player] = clock

	local data = DataHandler:GetData(player)
	if not data then
		return "limited_not_on_sale"
	end
	if owns(player, item.Id) then
		return "limited_owned"
	end
	-- A paid prompt whose receipt has not landed yet still reads as not owned; a second prompt in
	-- that window would charge for a copy the player is about to own.
	local pendingAt = self.PendingAt[player]
	if data.Cloud.LimitedPending ~= "" and pendingAt and clock - pendingAt < Config.PendingSeconds then
		return "limited_cooldown"
	end
	if item.Sold >= item.Config.Stock then
		return "limited_sold_out"
	end
	if not slot or slot.productId <= 0 then
		return "limited_not_on_sale"
	end

	-- Bound before the prompt: a receipt that lands after the window closes still buys this item.
	data.Cloud.LimitedPending = item.Id
	self.PendingAt[player] = clock
	PurchaseHandler:PurchaseProduct(player, slot.productId)
	return ""
end

--- A slot receipt was granted: hand over the item it bought.
function LimitedHandler.GrantSlot(self: LimitedHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local pending = data.Cloud.LimitedPending
	local pendingItem = if typeof(pending) == "string" then self.Items[pending] else nil
	data.Cloud.LimitedPending = ""
	self.PendingAt[player] = nil
	-- Bus.Limited.Buy always records the item, so a receipt without one came from a prompt opened
	-- some other way. Only the drop on sale with copies left is honoured then; anything else would
	-- skip the window and stock checks.
	local active = if pendingItem then nil else self:ActiveItem()
	local item = pendingItem or (if active and active.Sold < active.Config.Stock then active else nil)

	if not item then
		Logger:Error(`{player.Name} paid for the limited slot with no item pending or on sale; compensate by hand`)
		return
	end
	if owns(player, item.Id) then
		-- The prompt refuses owners, so this is a second receipt for one prompt window. Logged so it
		-- can be refunded or compensated by hand.
		Logger:Error(`{player.Name} bought {item.Id} again; the copy was already owned`)
		return
	end

	if data.Cloud.Limited == nil then
		data.Cloud.Limited = {}
	end
	data.Cloud.Limited[item.Id] = 0
	self:AddPass(player, item)
	self:ApplySkinFor(player)
	Logger:Info(`{player.Name} bought {item.Id}`)

	task.spawn(function()
		self:AssignSerial(player, item)
	end)
end

--- The item's Products row in Cloud.Passes is what the stat and multiplier sums read.
function LimitedHandler.AddPass(_self: LimitedHandler, player: Player, item: ItemState): ()
	local data = DataHandler:GetData(player)
	if not data or DataList.Contains(data.Cloud.Passes, item.Entry.id) then
		return
	end
	DataList.Append(data.Cloud.Passes, item.Entry.id)
	-- A pass can change what a stat is worth, and the cache in front of that stat is not ours.
	UpgradeHandler:Invalidate(player)
end

function LimitedHandler.RestoreOwned(self: LimitedHandler, player: Player): ()
	for _, item in self.Items do
		if not owns(player, item.Id) then
			continue
		end
		self:AddPass(player, item)
		if not serialOf(player, item.Id) then
			task.spawn(function()
				self:AssignSerial(player, item)
			end)
		end
	end
end

--- Numbers the owner's copy. Runs once per owner: a serial already in the profile is kept.
function LimitedHandler.AssignSerial(self: LimitedHandler, player: Player, item: ItemState): ()
	for attempt = 1, Config.SerialRetries do
		if serialOf(player, item.Id) or not owns(player, item.Id) or player.Parent ~= Players then
			return
		end

		local ok, result = pcall(self.Store.UpdateAsync, self.Store, item.Id, function(old: any): number
			return (if typeof(old) == "number" then old else 0) + 1
		end)

		if ok and typeof(result) == "number" then
			self:RecordSerial(player, item, result)
			return
		end

		Logger:Warn(`Serial for {player.Name} ({item.Id}) failed, attempt {attempt}: {result}`)
		task.wait(Config.SerialRetryDelay)
	end
end

function LimitedHandler.RecordSerial(self: LimitedHandler, player: Player, item: ItemState, serial: number): ()
	local owned = ownedTable(player)
	if not owned then
		-- The counter moved but the profile left; the next join assigns a new number. Rare, and a
		-- skipped number is harmless.
		Logger:Warn(`{player.Name} left before serial {serial} of {item.Id} was saved`)
		return
	end

	owned[item.Id] = serial
	if serial > item.Config.Stock then
		Logger:Warn(`{item.Id} oversold: {player.Name} got #{serial} of {item.Config.Stock}`)
	end
	Logger:Info(`{player.Name} owns {item.Id} #{serial}`)

	self:SetSold(item, serial)
	local buyer = string.sub(player.DisplayName, 1, MAX_BUYER_NAME)
	Bus.Limited.Sold:Fire(item.Id, buyer, serial)

	task.spawn(function()
		local payload = { i = item.Id, s = serial, b = buyer, j = game.JobId }
		local ok, result = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, payload)
		if not ok then
			Logger:Warn(`Publish to {TOPIC} failed: {result}`)
		end
	end)
end

--- Dresses the owner's ovens in the first owned item that has an oven surface.
function LimitedHandler.ApplySkinFor(self: LimitedHandler, player: Player): ()
	local bakery = BaseHandler:GetBase(player)
	if not bakery or self.Skins[bakery] then
		return
	end

	for _, item in self.Items do
		if item.Config.OvenSurface and owns(player, item.Id) then
			self:ApplySkin(bakery, item)
			return
		end
	end
end

function LimitedHandler.ApplySkin(self: LimitedHandler, bakery: Folder, item: ItemState): ()
	local assets = ReplicatedStorage:FindFirstChild(Config.AssetsFolder)
	local surfaceName = item.Config.OvenSurface
	local template = assets and surfaceName and assets:FindFirstChild(surfaceName)
	local rootPath = item.Config.OvenRoot
	local root = rootPath and resolvePath(bakery, rootPath)
	if not template or not template:IsA("SurfaceAppearance") or not root then
		Logger:Warn(`Cannot skin ovens in {bakery.Name}: surface or oven root missing`)
		return
	end

	-- SurfaceAppearance maps cannot be written at runtime, so the whole surface is swapped and the
	-- authored one is kept aside to restore when the bakery changes hands.
	local skinned: { SkinnedPart } = {}
	for _, model in root:GetDescendants() do
		if not model:IsA("Model") or model.Name ~= item.Config.OvenModel then
			continue
		end
		for _, part in model:GetDescendants() do
			if not part:IsA("MeshPart") then
				continue
			end
			local original = part:FindFirstChildOfClass("SurfaceAppearance")
			if not original then
				continue
			end
			local golden = template:Clone()
			original.Parent = nil
			golden.Parent = part
			table.insert(skinned, { Part = part, Original = original, Golden = golden })
		end
	end

	self.Skins[bakery] = skinned
end

function LimitedHandler.RemoveSkin(self: LimitedHandler, bakery: Folder): ()
	local skinned = self.Skins[bakery]
	if not skinned then
		return
	end
	self.Skins[bakery] = nil

	for _, entry in skinned do
		entry.Golden:Destroy()
		entry.Original.Parent = entry.Part
	end
end

export type LimitedHandler = typeof(LimitedHandler) & {
	Items: { [string]: ItemState },
	Skins: { [Folder]: { SkinnedPart } },
	LastBuy: { [Player]: number },
	PendingAt: { [Player]: number },
	Showcases: { Model },
	ShownItem: string?,
	Slot: Products.ProductEntry?,
	Store: DataStore,
}

return LimitedHandler :: LimitedHandler
