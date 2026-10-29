--!strict
-- Contextual Robux offers (Configs/Offers): Double Profit after a shift, Rescue Dish when a dish
-- burns in the oven, Keep Guests when a guest is about to walk out. This handler decides when each is
-- prompted and what its receipt pays; PurchaseHandler still owns the prompts and the receipts.
--
-- A receipt is final, so every grant pays something: the moment it was bought for when that is still
-- there, its coin fallback when it is gone. Coins go through EconomyHandler as "IAP", like a coin pack.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local BuildingHandler = require(_Handlers.BuildingHandler)
local Bus = require(_Shared.Bus)
local Config = require(_Configs.Offers)
local DataHandler = require(_Handlers.DataHandler)
local DayCycleHandler = require(_Handlers.DayCycleHandler)
local EconomyHandler = require(_Handlers.EconomyHandler)
local Format = require(_Shared.UI.Format)
local LoggerUtil = require(_Shared.Libs.Logger)
local Products = require(_Configs.Registries.Products)
local PurchaseHandler = require(_Handlers.PurchaseHandler)
local Recipes = require(_Configs.Registries.Recipes)

--[[ Types ]]--
-- os.clock of the last automatic prompt of any offer, and of each offer.
type PromptLog = { Any: number, Offers: { [string]: number } }

-- The dish that burned last, so the rescue knows which oven to open.
type BurntDish = { BuildingId: string, RecipeId: string }

--[[ Constants ]]--
local OFFERS: { [Config.OfferName]: Config.Offer } = {
	DoubleShift = Config.DoubleShift,
	RescueDish = Config.RescueDish,
	KeepGuest = Config.KeepGuest,
}

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "OfferHandler" })

--[[ Tables ]]--
local OfferHandler = {
	dependencies = { "DataHandler", "PurchaseHandler", "EconomyHandler", "DayCycleHandler", "BuildingHandler" },
}

--[[ Private Functions ]]--
-- The offer's product, only once it has a real id: an unset one is not on sale.
local function GetEntry(offer: Config.OfferName): Products.ProductEntry?
	local entry = Products:Get(OFFERS[offer].Product)
	return if entry and entry.productId > 0 then entry else nil
end

-- Pays through the wallet, so passes count as they do on a coin pack; returns what landed.
local function Pay(player: Player, coins: number, entry: Products.ProductEntry): number
	local before = EconomyHandler:GetCash(player)
	EconomyHandler:AddCash(player, coins, "IAP", entry.id)
	return EconomyHandler:GetCash(player) - before
end

local function Notify(player: Player, message: string): ()
	Bus.Progress.RewardGranted:FireClient(player, message)
end

--[[ Handling ]]--
function OfferHandler.OnInit(self: OfferHandler): ()
	self.Prompts = {}
	self.Burnt = {}
	self.RequestedAt = {}
end

function OfferHandler.OnStart(self: OfferHandler): ()
	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number)
		local entry = Products:GetByProductId(productId)
		if entry and entry.productId > 0 then
			self:Grant(player, entry)
		end
	end)

	DayCycleHandler.ShiftEnded:Connect(function(player: Player)
		self:RecordShift(player)
	end)

	BuildingHandler.StateChanged:Connect(function(player: Player, building: any, state: string, previous: string?)
		if state == "Burnt" and previous == "Ready" then
			self:NoticeBurn(player, building)
		end
	end)

	Bus.Offer.Request.OnServerEvent:Connect(function(player: Player, offer: any)
		self:Request(player, offer)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.Prompts[player] = nil
		self.Burnt[player] = nil
		self.RequestedAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.KeepGuest.CheckInterval)
			for _, player in Players:GetPlayers() do
				self:CheckGuests(player)
			end
		end
	end)
end

--- Whether an automatic prompt of `offer` may open now: on sale, past the tutorial and the first
--- days, and outside both cooldowns.
function OfferHandler.CanPrompt(self: OfferHandler, player: Player, offer: Config.OfferName): boolean
	local data = DataHandler:GetData(player)
	if not data or not GetEntry(offer) then
		return false
	end
	if not Config.IsUnlocked(data.Cloud) then
		return false
	end

	local log = self.Prompts[player]
	if not log then
		return true
	end
	local now = os.clock()
	local last = log.Offers[offer]
	return now - log.Any >= Config.GlobalCooldown and (last == nil or now - last >= OFFERS[offer].Cooldown)
end

--- Opens the Roblox prompt for `offer` and starts its cooldowns.
function OfferHandler.Prompt(self: OfferHandler, player: Player, offer: Config.OfferName): ()
	local entry = GetEntry(offer)
	if not entry then
		return
	end

	local now = os.clock()
	local log: PromptLog = self.Prompts[player] or { Any = -math.huge, Offers = {} }
	log.Any = now
	log.Offers[offer] = now
	self.Prompts[player] = log

	PurchaseHandler:PurchaseProduct(player, entry.productId)
	Logger:Info(`Offered {offer} to {player.Name}`)
end

--- A press on the report's Double Profit button or on the HUD offer button. Prompts only while the
--- offer still applies, so a stale button cannot sell a moment that is gone.
function OfferHandler.Request(self: OfferHandler, player: Player, offer: any): ()
	if offer ~= "DoubleShift" and offer ~= "RescueDish" and offer ~= "KeepGuest" then
		return
	end

	local now = os.clock()
	if now - (self.RequestedAt[player] or -math.huge) < Config.RequestCooldown then
		return
	end
	self.RequestedAt[player] = now

	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local applies = if offer == "DoubleShift"
		then Config.CanDoubleShift(data.Cloud.DoubleShift, data.Session.Day)
		else Config.IsUnlocked(data.Cloud) and Config.Applies(offer, data.Session, workspace:GetServerTimeNow())
	if applies then
		self:Prompt(player, offer)
	end
end

--- Hands over what an offer's receipt bought.
function OfferHandler.Grant(self: OfferHandler, player: Player, entry: Products.ProductEntry): ()
	local meta = entry.meta
	if not meta or not meta.offer then
		return
	end

	if meta.grant == "DoubleShift" then
		self:GrantDoubleShift(player, entry)
	elseif meta.grant == "RescueDish" then
		self:GrantRescue(player, entry)
	elseif meta.grant == "KeepGuest" then
		self:GrantKeepGuest(player, entry)
	end
	Logger:Info(`{player.Name} bought {entry.id}`)
end

--[[ Double Profit ]]--
--- Keeps the finished shift's profit in the save and, every few shifts, prompts once the report is up.
function OfferHandler.RecordShift(self: OfferHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local day = data.Session.Day
	local record = data.Cloud.DoubleShift
	record.Day = day.Number
	record.Coins = day.Summary.Coins
	record.Doubled = false

	local spec = Config.DoubleShift
	if day.Number % spec.PromptEveryShifts ~= 0 or not Config.CanDoubleShift(record, day) then
		return
	end
	task.delay(spec.PromptDelay, function()
		local current = DataHandler:GetData(player)
		if
			current
			and Config.CanDoubleShift(current.Cloud.DoubleShift, current.Session.Day)
			and self:CanPrompt(player, "DoubleShift")
		then
			self:Prompt(player, "DoubleShift")
		end
	end)
end

function OfferHandler.GrantDoubleShift(_self: OfferHandler, player: Player, entry: Products.ProductEntry): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local record = data.Cloud.DoubleShift
	local paid = Pay(player, math.max(record.Coins, Config.DoubleShift.MinCoins), entry)
	record.Doubled = true

	-- The report still open on that evening shows the doubled profit.
	local day = data.Session.Day
	if day.Phase == "Summary" and day.Number == record.Day then
		day.Summary.Coins = day.Summary.Coins + paid
	end
	Notify(player, `Profit doubled! +{Format.Number(paid)} coins`)
end

--[[ Rescue Dish ]]--
function OfferHandler.NoticeBurn(self: OfferHandler, player: Player, building: any): ()
	self.Burnt[player] = { BuildingId = building.Id, RecipeId = building.State.RecipeId or "" }
	if self:CanPrompt(player, "RescueDish") then
		self:Prompt(player, "RescueDish")
	end
end

--- The station still holding a burnt dish: the one the offer was made for first, else any.
function OfferHandler.FindBurnt(_self: OfferHandler, player: Player, preferredId: string?): any?
	local preferred = if preferredId then BuildingHandler:GetBuilding(player, preferredId) else nil
	if preferred and preferred:GetState() == "Burnt" then
		return preferred
	end

	for _, building in BuildingHandler:GetBuildings(player) do
		if building.Definition.Class == "Station" and building:GetState() == "Burnt" then
			return building
		end
	end
	return nil
end

function OfferHandler.GrantRescue(self: OfferHandler, player: Player, entry: Products.ProductEntry): ()
	local burnt = self.Burnt[player]
	self.Burnt[player] = nil

	local building = self:FindBurnt(player, if burnt then burnt.BuildingId else nil)
	if building then
		-- Ready starts its burn timer from ReadyAt, so the rescued dish gets the full time again. An
		-- oven whose fire went out after the burn holds that timer until it is refuelled, as it would
		-- have for a dish that finished cold.
		local state = building.State
		local now = workspace:GetServerTimeNow()
		state.ReadyAt = now
		if building.Definition.UsesFuel and state.Fuel == 0 then
			state.HeatPausedAt = now
		end
		building:SetState("Ready")
		Notify(player, "Dish rescued! Take it out of the oven.")
		return
	end

	-- Already thrown out: the dish's price instead.
	local recipe = if burnt then Recipes:Get(burnt.RecipeId) else nil
	local paid = Pay(player, if recipe then recipe.price else Config.RescueDish.FallbackCash, entry)
	Notify(player, `The dish was already gone: +{Format.Number(paid)} coins instead`)
end

--[[ Keep Guests ]]--
--- Prompts once a waiting guest is close to walking out.
function OfferHandler.CheckGuests(self: OfferHandler, player: Player): ()
	if not DayCycleHandler:IsShiftActive(player) or not self:CanPrompt(player, "KeepGuest") then
		return
	end

	local data = DataHandler:GetData(player)
	if data and Config.Applies("KeepGuest", data.Session, workspace:GetServerTimeNow()) then
		self:Prompt(player, "KeepGuest")
	end
end

function OfferHandler.GrantKeepGuest(_self: OfferHandler, player: Player, entry: Products.ProductEntry): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local now = workspace:GetServerTimeNow()
	local kept = 0
	-- Index each guest through the proxy: iteration yields the raw tables, and a write there would
	-- never replicate, leaving the client's patience bars empty.
	local customers = data.Session.Customers
	for customerId in customers do
		local customer = customers[customerId]
		if Config.PatienceLeft(customer, now) then
			customer.PatienceEndsAt = now + customer.Patience
			kept += 1
		end
	end

	if kept > 0 then
		Notify(player, if kept == 1 then "Your guest will wait a little longer" else `{kept} guests will wait a little longer`)
		return
	end
	local paid = Pay(player, Config.KeepGuest.FallbackCash, entry)
	Notify(player, `Nobody was waiting: +{Format.Number(paid)} coins instead`)
end

export type OfferHandler = typeof(OfferHandler) & {
	Prompts: { [Player]: PromptLog },
	Burnt: { [Player]: BurntDish },
	RequestedAt: { [Player]: number },
}

return OfferHandler :: OfferHandler
