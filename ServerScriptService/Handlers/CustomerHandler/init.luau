--!strict
-- Shift customers: flow, queue, orders, patience and the payout for a served dish.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local CatHandler = require(ServerScriptService.Handlers.CatHandler)
local CatsConfig = require(_Configs.Cats)
local CustomerTypes = require(_Configs.Registries.CustomerTypes)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local DayCycleConfig = require(_Configs.DayCycle)
local DayCycleHandler = require(ServerScriptService.Handlers.DayCycleHandler)
local DisplayHandler = require(ServerScriptService.Handlers.DisplayHandler)
local DisplayCustomers = require(_Configs.DisplayCustomers)
local Economy = require(_Configs.Economy)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local GuestState = require(script.GuestState)
local InventoryHandler = require(ServerScriptService.Handlers.InventoryHandler)
local LoggerUtil = require(_Libs.Logger)
local Recipes = require(_Configs.Registries.Recipes)
local Sanitize = require(_Shared.Sanitize)
local Signal = require(_Libs.Signal)
local GuestsConfig = require(_Configs.Guests)
local Street = require(script.Parent.CustomerViewHandler.Street)
local TableHandler = require(ServerScriptService.Handlers.TableHandler)
local TickHandler = require(ServerScriptService.Handlers.TickHandler)
local Tips = require(_Shared.Tips)
local TutorialConfig = require(_Configs.Tutorial)
local TutorialPolicy = require(_Shared.TutorialPolicy)
local TutorialEvents = require(ServerScriptService.TutorialEvents)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)
local VFXRules = require(_Shared.VFXRules)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "CustomerHandler" })

--[[ Tables ]]--
local CustomerHandler = {
	dependencies = {
		"DataHandler",
		"TickHandler",
		"DayCycleHandler",
		"TableHandler",
		"DisplayHandler",
		"InventoryHandler",
		"EconomyHandler",
		"UpgradeHandler",
		"CatHandler",
	},
	priority = 40,
}

-- Lifecycle of one guest, for whoever draws them in the world. The data stays the only state;
-- these are notifications about it, not a second copy.
CustomerHandler.CustomerSpawned = Signal() :: Signal.Signal<Player, string>
CustomerHandler.CustomerSeated = Signal() :: Signal.Signal<Player, string, string>
CustomerHandler.CustomerEating = Signal() :: Signal.Signal<Player, string, string, string>
CustomerHandler.CustomerLeft = Signal() :: Signal.Signal<Player, string, boolean>
CustomerHandler.CustomerShopping = Signal() :: Signal.Signal<Player, string>
CustomerHandler.CustomerPurchased = Signal() :: Signal.Signal<Player, string>
CustomerHandler.CustomerAdopted = Signal() :: Signal.Signal<Player, string>

--[[ Private Functions ]]--
local function GetCustomers(player: Player): any?
	local data = DataHandler:GetData(player)
	return data and data.Session.Customers
end

local function CountCustomers(customers: any): number
	local count = 0
	for _ in customers do
		count += 1
	end

	return count
end

-- Reserve waiting space before the yielding avatar load, and retain it until this guest leaves.
local function FreePosition(customers: any, field: string, limit: number): number?
	local occupied: { [number]: boolean } = {}
	for _, customer in customers do
		local index = customer[field]
		if index then
			occupied[index] = true
		end
	end
	for index = 1, limit do
		if not occupied[index] then
			return index
		end
	end
	return nil
end

local function PickWeighted(entries: { CustomerTypes.CustomerTypeEntry }): CustomerTypes.CustomerTypeEntry?
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end

	if total <= 0 then
		return nil
	end

	local roll = math.random() * total
	for _, entry in entries do
		roll -= entry.weight
		if roll <= 0 then
			return entry
		end
	end

	return entries[#entries]
end

-- The order is built from the day menu: customers ask for whatever the player cooks today.
local function RollOrders(menu: { string }, entry: CustomerTypes.CustomerTypeEntry): { string }
	local orders: { string } = {}
	if #menu == 0 then
		return orders
	end

	for _ = 1, entry.orders do
		orders[#orders + 1] = menu[math.random(#menu)]
	end

	return orders
end

local function PickType(player: Player, kind: string): CustomerTypes.CustomerTypeEntry?
	local entries = {}
	for _, entry in CustomerTypes:GetAvailable(EconomyHandler:GetLevel(player)) do
		if entry.kind == kind then
			entries[#entries + 1] = entry
		end
	end
	return PickWeighted(entries)
end

-- An early guest follows the current batch, with a feasible menu recipe as fallback.
local function ScriptedOrder(player: Player): string?
	local data = DataHandler:GetData(player)
	return data and TutorialPolicy.FirstOrder(data.Cloud, data.Session)
end

--[[ Handling ]]--
function CustomerHandler.OnInit(self: CustomerHandler): ()
	self.Runtime = {}
	self.Guests = {}
end

function CustomerHandler.OnStart(self: CustomerHandler): ()
	DayCycleHandler.ShiftStarted:Connect(function(player: Player)
		self:StartShift(player)
	end)

	DayCycleHandler.ShiftEnded:Connect(function(player: Player)
		self:ClearCustomers(player)
	end)

	TableHandler.TableCleaned:Connect(function(player: Player)
		self:SeatQueue(player)
	end)

	TickHandler.Tick:Connect(function()
		self:UpdateCustomers()
	end)

	Bus.Cafe.Serve.OnServerEvent:Connect(function(player: Player, customerId: any)
		local id = Sanitize.Id(customerId)
		if id then
			self:Serve(player, id)
		end
	end)
	Bus.Cafe.TakeOrder.OnServerEvent:Connect(function(player: Player, customerId: any)
		local id = Sanitize.Id(customerId)
		if id then
			self:TakeOrder(player, id)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:ClearCustomers(player)
		self.Runtime[player] = nil
	end)
end

-- Seats plus display slots: the customer flow is scaled to it, so a bigger bakery gets busier.
function CustomerHandler.GetCapacity(_self: CustomerHandler, player: Player): number
	local tables = UpgradeHandler:GetStat(player, "TableCount")

	return DayCycleConfig.GetCapacity(tables, DisplayHandler:GetGuestCapacity(player))
end

function CustomerHandler.StartShift(self: CustomerHandler, player: Player): ()
	self:ClearCustomers(player)

	local previous = self.Runtime[player]
	local data = DataHandler:GetData(player)

	self.Runtime[player] = {
		DisplayFlow = if previous then previous.DisplayFlow else 1,
		NextSpawnAt = workspace:GetServerTimeNow() + DayCycleConfig.FirstSpawnDelay,
		-- Ids never restart: a guest walking out still owns their body while the next shift spawns.
		NextId = if previous then previous.NextId else 1,
		ScriptedGuest = data ~= nil and TutorialPolicy.IsActive(data.Cloud),
	}
end

function CustomerHandler.ClearCustomers(self: CustomerHandler, player: Player): ()
	for _, guest in (self.Guests[player] or {}) :: { [string]: GuestState.GuestState } do
		guest:Destroy()
	end
	self.Guests[player] = nil
	local customers = GetCustomers(player)
	if not customers then
		return
	end

	for customerId in customers do
		Street.Cancel(player, customerId)
		CatHandler:Release(player, customerId)
		local tableId = customers[customerId].TableId
		if tableId then
			TableHandler:Release(player, tableId, customerId)
		end

		customers[customerId] = nil
		self.CustomerLeft:Fire(player, customerId, false)
	end
end

function CustomerHandler.SpawnCustomer(self: CustomerHandler, player: Player): boolean
	local data = DataHandler:GetData(player)
	local runtime = self.Runtime[player]
	if not data or not runtime or not DayCycleHandler:CanAcceptCustomers(player) then
		return false
	end

	local scriptedEntry: CustomerTypes.CustomerTypeEntry? = nil
	local scriptedOrders: { string }? = nil

	if runtime.ScriptedGuest then
		local recipeId = ScriptedOrder(player)
		local scripted = CustomerTypes:Get(TutorialConfig.FirstGuestType)
		if recipeId and scripted then
			scriptedEntry = scripted
			scriptedOrders = { recipeId }
		end
	end

	local hasDisplay = DisplayHandler:GetGuestCapacity(player) > 0
	local kind = if hasDisplay and math.random() > DisplayCustomers.SeatedChance then "Display" else "Seated"
	local entry = scriptedEntry or PickType(player, kind)
	if not entry then
		return false
	end

	local tableId = if entry.kind == "Seated" then TableHandler:FindFree(player) else nil
	-- Original visitors browse the store when dining places are full and displays are unlocked.
	if not scriptedEntry and entry.kind == "Seated" and not tableId then
		if not hasDisplay then
			return false
		end
		entry = PickType(player, "Display")
		if not entry then
			return false
		end
	end
	local orders = scriptedOrders or (if entry.kind == "Display" then {} else RollOrders(data.Session.Day.Menu, entry))
	if entry.kind == "Seated" and #orders == 0 then
		return false
	end

	local customerId = `guest_{runtime.NextId}`

	local queuePosition = if entry.kind == "Seated" and not tableId
		then FreePosition(data.Session.Customers, "QueuePosition", DayCycleConfig.QueueSlack)
		else nil
	local displayPosition = if entry.kind == "Display"
		then FreePosition(data.Session.Customers, "DisplayPosition", DisplayHandler:GetGuestCapacity(player))
		else nil
	-- Display capacity must never turn into an unbounded dining queue.
	if entry.kind == "Seated" and not tableId and not queuePosition then
		return false
	end
	if entry.kind == "Display" and not displayPosition then
		return false
	end
	if not Street.Take(player, customerId) then
		return false
	end
	runtime.NextId += 1
	if scriptedEntry then
		runtime.ScriptedGuest = false
	end
	local seatIndex = if tableId then TableHandler:Occupy(player, tableId, customerId) else nil
	if not seatIndex then
		tableId = nil
	end

	-- Protection pauses expiry. Keep the normal patience duration for when guidance is skipped.
	local patience = entry.patience

	data.Session.Customers[customerId] = {
		TypeId = entry.id,
		Kind = entry.kind,
		-- A seated customer with no free table waits in the queue, but patience already ticks.
		State = if entry.kind == "Display" or tableId then "Arriving" else "Queued",
		TableId = tableId,
		SeatIndex = seatIndex,
		QueuePosition = queuePosition,
		DisplayPosition = displayPosition,
		Orders = orders,
		-- Stored per guest so the released deadline and patience bar share one duration.
		Patience = patience,
		TutorialProtected = scriptedEntry ~= nil,
		PatienceEndsAt = workspace:GetServerTimeNow() + patience,
		ChoosingEndsAt = 0,
		OrderStartedAt = 0,
		EatEndsAt = 0,
	}

	local customer = data.Session.Customers[customerId]
	if scriptedEntry then
		local context = data.Session.Tutorial
		context.RecipeId = orders[1]
		context.GuestId = customerId
		context.TableId = tableId or ""
		context.SeatIndex = seatIndex or 0
	end
	self.Guests[player] = self.Guests[player] or {}
	self.Guests[player][customerId] = GuestState.new(customer, function(): ()
		if customer.TableId then
			TableHandler:TakeOrder(player, customer.TableId, customerId)
		end
	end, function(served: boolean): ()
		self:FinishCustomer(player, customerId, customer, served)
	end)
	self.CustomerSpawned:Fire(player, customerId)
	return true
end

-- A table freed up — seat the queue in arrival order. Guest ids carry their spawn number, and the
-- proxy iterates in hash order, so the queue is sorted by that number: the guest standing first in
-- line is the one who gets the table.
function CustomerHandler.SeatQueue(self: CustomerHandler, player: Player): ()
	if not DayCycleHandler:CanAcceptCustomers(player) then
		return
	end
	local customers = GetCustomers(player)
	if not customers then
		return
	end

	local queued: { string } = {}
	for customerId in customers do
		if customers[customerId].State == "Queued" then
			table.insert(queued, customerId)
		end
	end

	table.sort(queued, function(left: string, right: string)
		return (tonumber(left:match("_(%d+)$")) or 0) < (tonumber(right:match("_(%d+)$")) or 0)
	end)

	-- The customer is re-read through the proxy: writes on the iteration value do not replicate.
	for _, customerId in queued do
		local customer = customers[customerId]

		local tableId = TableHandler:FindFree(player)
		if not tableId then
			return
		end

		local seatIndex = TableHandler:Occupy(player, tableId, customerId)
		if seatIndex then
			customer.QueuePosition = nil
			customer.TableId = tableId
			customer.SeatIndex = seatIndex
			local guest = self.Guests[player] and self.Guests[player][customerId]
			if guest then
				guest:Seat()
			end
			self.CustomerSeated:Fire(player, customerId, tableId)
		end
	end
end

-- The world view reports completion of the server-owned route. Late callbacks are harmless.
function CustomerHandler.ArriveAtSeat(self: CustomerHandler, player: Player, customerId: string): ()
	local guest = self.Guests[player] and self.Guests[player][customerId]
	if guest then
		guest:Arrive()
	end
end

-- Body callbacks never sell food from a different pedestal or buy twice after a late arrival.
function CustomerHandler.ArriveAtDisplay(self: CustomerHandler, player: Player, customerId: string): ()
	local customers = GetCustomers(player)
	local customer = customers and customers[customerId]
	if not customer or customer.Kind ~= "Display" then
		return
	end
	local guest = self.Guests[player] and self.Guests[player][customerId]
	if not guest then
		return
	end
	local now = workspace:GetServerTimeNow()
	if customer.State == "Arriving" then
		guest:Browse()
		customer.BrowseEndsAt = now + math.random(DisplayCustomers.BrowseMinSeconds, DisplayCustomers.BrowseMaxSeconds)
	end
	if customer.State == "Browsing" then
		customer.RoamAt = now + math.random(DisplayCustomers.RoamPauseMinSeconds, DisplayCustomers.RoamPauseMaxSeconds)
	elseif customer.State == "Shopping" then
		if not customer.DisplaySlot then
			return
		end
		local recipeId, leftover = DisplayHandler:TakeSlot(player, customer.DisplaySlot)
		if not recipeId then
			self:FinishCustomer(player, customerId, customer, false)
			return
		end
		guest:Purchase()
		self:PayForDish(player, customer, recipeId, if leftover then DisplayCustomers.LeftoverPriceMultiplier else 1)
		customer.PurchaseEndsAt = now + DisplayCustomers.PurchaseSeconds
		self.CustomerPurchased:Fire(player, customerId)
	end
end

-- A duplicate route callback never restarts the adoption clock.
function CustomerHandler.ArriveAtCat(_self: CustomerHandler, player: Player, customerId: string, position: Vector3): ()
	local customers = GetCustomers(player)
	local customer = customers and customers[customerId]
	if not customer or customer.State ~= "Adopting" or customer.AdoptEndsAt then
		return
	end
	local cat = CatHandler:GetReserved(player, customer.CatId, customerId)
	if not cat or ((position - cat.Approach) * Vector3.new(1, 0, 1)).Magnitude > 4 then
		return
	end
	customer.AdoptEndsAt = workspace:GetServerTimeNow() + CatsConfig.AdoptSeconds
end

-- A failed physical seat must not become a phantom order in the HUD.
function CustomerHandler.AbortArrival(self: CustomerHandler, player: Player, customerId: string): ()
	local customers = GetCustomers(player)
	local customer = customers and customers[customerId]
	if customer and customer.State == "Arriving" then
		self:FinishCustomer(player, customerId, customer, false)
	end
end

function CustomerHandler.TakeOrder(self: CustomerHandler, player: Player, customerId: string): boolean
	local customers = GetCustomers(player)
	local customer = customers and customers[customerId]
	if not customer or customer.State ~= "Choosing" or not customer.TableId then
		return false
	end
	if not TableHandler:CanServe(player, customer.TableId, customerId) then
		return false
	end
	local guests = self.Guests[player]
	local guest: GuestState.GuestState? = if guests then guests[customerId] else nil
	local accepted = guest ~= nil and guest:TakeOrder()
	if accepted then
		TutorialEvents.Action:Fire(player, "TakeOrder", customerId)
	end
	return accepted
end

-- Serving a dish from hands: any order of this customer that matches what is carried will do.
function CustomerHandler.Serve(self: CustomerHandler, player: Player, customerId: string): boolean
	local customers = GetCustomers(player)
	local customer = customers and customers[customerId]
	if not customer or customer.State ~= "Waiting" or not customer.TableId then
		return false
	end
	if not TableHandler:CanServe(player, customer.TableId, customerId) then
		return false
	end

	local held = InventoryHandler:Peek(player)
	local rawRecipe = if held and held.Kind == "Dough" then Recipes:Get(held.Id) else nil
	if rawRecipe and rawRecipe.station == "Oven" then
		Bus.Progress.ActionFailed:FireClient(player, "bake_before_serving")
		return false
	end

	if not held or held.Kind ~= "Dish" then
		Bus.Progress.ActionFailed:FireClient(player, "nothing_to_serve")
		return false
	end

	if not DataList.Contains(customer.Orders, held.Id) then
		Bus.Progress.ActionFailed:FireClient(player, "wrong_dish")
		return false
	end

	InventoryHandler:Pop(player)

	local accepted = self:ServeDish(player, customerId, held.Id)
	if accepted then
		TutorialEvents.Action:Fire(player, "Serve", customerId)
	end
	return accepted
end

-- Closes one customer order with a dish already taken from anywhere: hands, display, assistant.
function CustomerHandler.ServeDish(self: CustomerHandler, player: Player, customerId: string, recipeId: string): boolean
	local customers = GetCustomers(player)
	local customer = customers and customers[customerId]
	if not customer or customer.State ~= "Waiting" then
		return false
	end

	if not DataList.RemoveValue(customer.Orders, recipeId) then
		return false
	end

	self:PayForDish(player, customer, recipeId)
	if customer.TableId then
		TableHandler:ServeMenu(player, customer.TableId, customerId, recipeId)
	end

	if #customer.Orders == 0 then
		self:StartEating(player, customerId, customer, recipeId)
	end

	return true
end

-- The last order is in: the guest stops being a timer and starts being a happy customer at the table.
-- The seat is only freed when they are done, so eating is a real part of the table throughput.
function CustomerHandler.StartEating(
	self: CustomerHandler,
	player: Player,
	customerId: string,
	customer: any,
	recipeId: string
): ()
	local guest = self.Guests[player] and self.Guests[player][customerId]
	if not guest then
		return
	end
	local reaction = if customer.TutorialProtected
		then "Happy"
		else VFXRules.Reaction(
			customer.Kind,
			customer.PatienceEndsAt,
			customer.Patience,
			workspace:GetServerTimeNow()
		)
	guest:Eat()

	self.CustomerEating:Fire(player, customerId, recipeId, reaction)
end

-- The customer waiting for exactly this dish. Needed by the assistant to carry coffee around.
function CustomerHandler.FindWaitingFor(_self: CustomerHandler, player: Player, recipeId: string): string?
	local customers = GetCustomers(player)
	if not customers then
		return nil
	end

	for customerId in customers do
		local customer = customers[customerId]
		if
			not customer.TutorialProtected
			and customer.State == "Waiting"
			and customer.TableId
			and DataList.Contains(customer.Orders, recipeId)
		then
			return customerId
		end
	end

	return nil
end

function CustomerHandler.PayForDish(
	_self: CustomerHandler,
	player: Player,
	customer: any,
	recipeId: string,
	priceMultiplier: number?
): ()
	local data = DataHandler:GetData(player)
	local entry = CustomerTypes:Get(customer.TypeId)
	local recipe = Recipes:Get(recipeId)
	if not data or not entry or not recipe then
		return
	end

	local patienceLeft = if customer.TutorialProtected
		then 1
		else math.clamp(
			(customer.PatienceEndsAt - workspace:GetServerTimeNow()) / (customer.Patience or entry.patience),
			0,
			1
		)

	-- Counter purchases are takeaways, with no timed table-service tip.
	local coins = if customer.Kind == "Display"
		then recipe.price * (priceMultiplier or 1)
		else Tips.GetSaleValue({
			recipeId = recipeId,
			patienceLeft = patienceLeft,
			customerMultiplier = entry.tipMultiplier,
			tipStat = UpgradeHandler:GetStat(player, "TipMult"),
			menuSize = #data.Session.Day.Menu,
			isNewRecipe = EconomyHandler:IsRecipeNew(player, recipeId),
		})

	local before = data.Cloud.Cash
	DayCycleHandler:AddResult(player, coins, Economy.GetDishXP(recipe.price), 0, 0)
	if customer.TutorialProtected then
		data.Session.Tutorial.LastSale = math.round((data.Cloud.Cash - before) * 100) / 100
		data.Session.Tutorial.SaleAt = workspace:GetServerTimeNow()
	end
end

-- Customer leaving: a happy one counts as served, an impatient one as a loss.
function CustomerHandler.FinishCustomer(
	self: CustomerHandler,
	player: Player,
	customerId: string,
	customer: any,
	served: boolean
): ()
	local customers = GetCustomers(player)
	if not customers then
		return
	end

	if customer.TableId then
		TableHandler:Release(player, customer.TableId, customerId)
	end

	local guests = self.Guests[player]
	local isDisplay = customer.Kind == "Display"
	CatHandler:Release(player, customerId)
	if guests and guests[customerId] then
		guests[customerId]:Destroy()
		guests[customerId] = nil
	end
	customers[customerId] = nil
	self.CustomerLeft:Fire(player, customerId, served)
	if isDisplay then
		local runtime = self.Runtime[player]
		if runtime then
			runtime.DisplayFlow = math.clamp(
				runtime.DisplayFlow + (if served then -DisplayCustomers.FlowChange else DisplayCustomers.FlowChange),
				DisplayCustomers.FlowMin,
				DisplayCustomers.FlowMax
			)
		end
		if not served then
			-- No patience failure or XP fine: this visitor simply found no stock.
			return
		end
	end

	if served then
		DayCycleHandler:AddResult(player, 0, 0, 1, 0)
		return
	end

	DayCycleHandler:AddResult(player, 0, -Economy.XPLostCustomer, 0, 1)
	Logger:Debug(`{player.Name}: guest {customerId} left with nothing`)
end

function CustomerHandler.ReleaseTutorial(self: CustomerHandler, player: Player): ()
	local now = workspace:GetServerTimeNow()
	local customers = GetCustomers(player)
	if not customers then
		return
	end
	for _, customer in customers do
		if not customer.TutorialProtected then
			continue
		end
		customer.TutorialProtected = false
		customer.PatienceEndsAt = now + customer.Patience
	end
	local runtime = self.Runtime[player]
	if runtime then
		runtime.ScriptedGuest = false
		runtime.NextSpawnAt = now + DayCycleConfig.FirstSpawnDelay
	end
end

function CustomerHandler.UpdateCustomers(self: CustomerHandler): ()
	local now = workspace:GetServerTimeNow()

	for _, player in Players:GetPlayers() do
		if not DayCycleHandler:IsShiftActive(player) then
			continue
		end

		self:UpdatePlayerCustomers(player, now)
	end
end

function CustomerHandler.UpdatePlayerCustomers(self: CustomerHandler, player: Player, now: number): ()
	local customers = GetCustomers(player)
	local runtime = self.Runtime[player]
	if not customers or not runtime then
		return
	end

	for customerId in customers do
		self:UpdateOneCustomer(player, customerId, customers[customerId], now)
	end
	-- Also catches newly bought tables; queued guests get seats before a new arrival can take one.
	self:SeatQueue(player)
	-- Existing orders keep progressing after last admission, but no new guest enters.
	if not DayCycleHandler:CanAcceptCustomers(player) then
		return
	end
	local data = DataHandler:GetData(player)
	if data and TutorialPolicy.IsActive(data.Cloud) then
		-- After the guest leaves, their place must be cleaned before another arrival.
		local stage = data.Session.Tutorial.Stage
		if CountCustomers(customers) > 0 or stage == "Clean" or stage == "Sweep" then
			return
		end
		if data.Session.Tutorial.GuestId ~= "" then
			return
		end
	end

	local capacity = self:GetCapacity(player)
	local hasCapacity = CountCustomers(customers) < DayCycleConfig.GetMaxActive(capacity)
	if hasCapacity and now >= runtime.NextSpawnAt - GuestsConfig.Street.AdmissionLeadSeconds then
		Street.Prepare(player)
	end
	if now < runtime.NextSpawnAt then
		return
	end

	-- A valid day always has a menu. Keep the guard for damaged session data without freezing the
	-- normal first-day flow just because the display was empty when the doors opened.
	if runtime.ScriptedGuest and not ScriptedOrder(player) then
		return
	end

	if hasCapacity then
		if not self:SpawnCustomer(player) then
			runtime.NextSpawnAt = now + GuestsConfig.Street.AdmissionRetrySeconds
			return
		end
	end

	runtime.NextSpawnAt = now + DayCycleConfig.GetSpawnInterval() * runtime.DisplayFlow
end

function CustomerHandler.UpdateOneCustomer(
	self: CustomerHandler,
	player: Player,
	customerId: string,
	customer: any,
	now: number
): ()
	local guest = self.Guests[player] and self.Guests[player][customerId]
	if not guest then
		return
	end
	guest:Update(now)
	local customers = GetCustomers(player)
	if not customers or not customers[customerId] then
		return
	end
	if customer.Kind == "Display" then
		self:UpdateShopper(player, customerId, customer, now)
	end
end

function CustomerHandler.UpdateShopper(
	self: CustomerHandler,
	player: Player,
	customerId: string,
	customer: any,
	now: number
): ()
	if customer.State == "Adopting" then
		if not CatHandler:GetReserved(player, customer.CatId, customerId) then
			self:FinishCustomer(player, customerId, customer, false)
		elseif customer.AdoptEndsAt and now >= customer.AdoptEndsAt then
			local adopted = CatHandler:Complete(player, customer.CatId, customerId)
			if adopted then
				self.CustomerAdopted:Fire(player, customerId)
			end
			self:FinishCustomer(player, customerId, customer, adopted)
		end
	elseif customer.State == "Purchasing" and now >= customer.PurchaseEndsAt then
		self:FinishCustomer(player, customerId, customer, true)
	elseif customer.State == "Browsing" then
		if now >= customer.BrowseEndsAt then
			local catId = CatHandler:Reserve(player, customerId)
			if catId then
				customer.CatId = catId
				self.Guests[player][customerId]:Adopt()
				self.CustomerShopping:Fire(player, customerId)
				return
			end
			local slot = DisplayHandler:FindStockedSlot(player)
			if not slot then
				Bus.Progress.ActionFailed:FireClient(player, "display_empty")
				self:FinishCustomer(player, customerId, customer, false)
				return
			end
			customer.DisplaySlot = slot
			customer.PatienceEndsAt = now + customer.Patience
			self.Guests[player][customerId]:Shop()
			self.CustomerShopping:Fire(player, customerId)
		elseif customer.RoamAt and now >= customer.RoamAt then
			customer.RoamAt = nil
			self.CustomerShopping:Fire(player, customerId)
		end
	end
end

export type CustomerHandler = typeof(CustomerHandler) & {
	Guests: { [Player]: { [string]: GuestState.GuestState } },
	Runtime: { [Player]: { NextSpawnAt: number, NextId: number, ScriptedGuest: boolean, DisplayFlow: number } },
}

return CustomerHandler :: CustomerHandler
