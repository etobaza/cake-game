--!strict
-- Small Robux offers (Configs/Offers): Double Profit, Rescue Dish and Keep Guests. They sell in the
-- Store like any product and are also prompted at the moment they help: after a shift, when a dish
-- burns in the oven, when a guest is about to walk out. This handler decides those prompts and what a
-- receipt does; PurchaseHandler still owns the prompts and the receipts.
--
-- A receipt works at once when its moment is there (the evening's profit, a burnt dish, an impatient
-- guest). Otherwise it is kept as a charge in Cloud.OfferCharges and spent automatically the next time
-- the moment comes, so a purchase from the Store is never wasted.

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

--[[ Types ]]--
-- os.clock of the last automatic prompt of any offer, and of each offer.
type PromptLog = { Any: number, Offers: { [string]: number } }

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

local function Notify(player: Player, message: string): ()
	Bus.Progress.RewardGranted:FireClient(player, message)
end

-- Banks one use of `offer` for its next moment.
local function AddCharge(player: Player, offer: Config.OfferName, message: string): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local charges = data.Cloud.OfferCharges
	charges[offer] = (charges[offer] or 0) + 1
	Notify(player, message)
end

-- Spends one banked use of `offer`; false when there is none.
local function TakeCharge(player: Player, offer: Config.OfferName): boolean
	local data = DataHandler:GetData(player)
	local charges = data and data.Cloud.OfferCharges
	if not charges or (charges[offer] or 0) <= 0 then
		return false
	end
	charges[offer] = charges[offer] - 1
	return true
end

-- The station holding a burnt dish: `preferred` first, else any.
local function FindBurnt(player: Player, preferred: any?): any?
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

-- Ready starts its burn timer from ReadyAt, so the rescued dish gets the full time again. An oven
-- whose fire went out after the burn holds that timer until it is refuelled, as it would have for a
-- dish that finished cold.
local function Rescue(player: Player, building: any): ()
	local state = building.State
	local now = workspace:GetServerTimeNow()
	state.ReadyAt = now
	if building.Definition.UsesFuel and state.Fuel == 0 then
		state.HeatPausedAt = now
	end
	building:SetState("Ready")
	Notify(player, "Dish rescued! Take it out of the oven.")
end

-- Refills every guest whose patience is running; returns how many.
local function KeepGuests(player: Player): number
	local data = DataHandler:GetData(player)
	if not data then
		return 0
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
	end
	return kept
end

-- Pays the recorded shift's profit again and shows it on the open report.
local function DoubleShift(player: Player): ()
	local data = DataHandler:GetData(player)
	local entry = Products:Get(Config.DoubleShift.Product)
	if not data or not entry then
		return
	end

	local record = data.Cloud.DoubleShift
	local before = EconomyHandler:GetCash(player)
	-- Through the wallet as "IAP", so passes count as they do on a coin pack.
	EconomyHandler:AddCash(player, record.Coins, "IAP", entry.id)
	local paid = EconomyHandler:GetCash(player) - before
	record.Doubled = true

	local day = data.Session.Day
	if day.Phase == "Summary" and day.Number == record.Day then
		day.Summary.Coins = day.Summary.Coins + paid
	end
	Notify(player, `Profit doubled! +{Format.Number(paid)} coins`)
end

--[[ Handling ]]--
function OfferHandler.OnInit(self: OfferHandler): ()
	self.Prompts = {}
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

	Players.PlayerRemoving:Connect(function(player: Player)
		self.Prompts[player] = nil
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

--- Hands over what an offer's receipt bought: now if its moment is there, else as a charge.
function OfferHandler.Grant(_self: OfferHandler, player: Player, entry: Products.ProductEntry): ()
	local meta = entry.meta
	local data = DataHandler:GetData(player)
	if not meta or not meta.offer or not data then
		return
	end

	if meta.grant == "DoubleShift" then
		if Config.CanDoubleShift(data.Cloud.DoubleShift, data.Session.Day) then
			DoubleShift(player)
		else
			AddCharge(player, "DoubleShift", "Saved! Your next shift's profit will be doubled.")
		end
	elseif meta.grant == "RescueDish" then
		local building = FindBurnt(player, nil)
		if building then
			Rescue(player, building)
		else
			AddCharge(player, "RescueDish", "Saved! The next dish that burns will be rescued.")
		end
	elseif meta.grant == "KeepGuest" then
		-- Only a guest about to walk out is the moment: patient guests would waste the purchase.
		local applies = Config.Applies("KeepGuest", data.Session, workspace:GetServerTimeNow())
		if not applies or KeepGuests(player) == 0 then
			AddCharge(player, "KeepGuest", "Saved! Guests about to leave will get more patience.")
		end
	end
	Logger:Info(`{player.Name} bought {entry.id}`)
end

--[[ Double Profit ]]--
--- Keeps the finished shift's profit in the save. A banked Double Profit doubles it at once;
--- otherwise, every few shifts, the offer is prompted once the report is up.
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

	if not Config.CanDoubleShift(record, day) then
		return
	end
	if TakeCharge(player, "DoubleShift") then
		DoubleShift(player)
		return
	end

	local spec = Config.DoubleShift
	if day.Number % spec.PromptEveryShifts ~= 0 then
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

--[[ Rescue Dish ]]--
--- A dish just burned: a banked Rescue Dish saves it, else the offer is prompted.
function OfferHandler.NoticeBurn(self: OfferHandler, player: Player, building: any): ()
	local data = DataHandler:GetData(player)
	local charges = data and data.Cloud.OfferCharges
	if charges and (charges.RescueDish or 0) > 0 then
		-- After the state change that told us: switching state inside its own signal is not safe.
		task.defer(function()
			local target = FindBurnt(player, building)
			if target and TakeCharge(player, "RescueDish") then
				Rescue(player, target)
			end
		end)
		return
	end
	if self:CanPrompt(player, "RescueDish") then
		self:Prompt(player, "RescueDish")
	end
end

--[[ Keep Guests ]]--
--- A guest is close to walking out: a banked Keep Guests refills them, else the offer is prompted.
function OfferHandler.CheckGuests(self: OfferHandler, player: Player): ()
	if not DayCycleHandler:IsShiftActive(player) then
		return
	end
	local data = DataHandler:GetData(player)
	if not data or not Config.Applies("KeepGuest", data.Session, workspace:GetServerTimeNow()) then
		return
	end

	if (data.Cloud.OfferCharges.KeepGuest or 0) > 0 then
		if KeepGuests(player) > 0 then
			TakeCharge(player, "KeepGuest")
		end
		return
	end
	if self:CanPrompt(player, "KeepGuest") then
		self:Prompt(player, "KeepGuest")
	end
end

export type OfferHandler = typeof(OfferHandler) & {
	Prompts: { [Player]: PromptLog },
}

return OfferHandler :: OfferHandler
