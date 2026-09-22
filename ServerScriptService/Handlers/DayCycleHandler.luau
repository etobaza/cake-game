--!strict
-- Day cycle: untimed prep, a timed shift, then manual end-of-day planning.
-- One StateMachine per player owns the phase transitions; other systems subscribe to the signals.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local DayCycleConfig = require(_Configs.DayCycle)
local DayReportConfig = require(_Configs.DayReport)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local Economy = require(_Configs.Economy)
local GameTypes = require(_Shared.GameTypes)
local LoggerUtil = require(_Libs.Logger)
local Ingredients = require(_Configs.Registries.Ingredients)
local Recipes = require(_Configs.Registries.Recipes)
local Sanitize = require(_Shared.Sanitize)
local Signal = require(_Libs.Signal)
local StateMachine = require(_Libs.StateMachine)
local TickHandler = require(ServerScriptService.Handlers.TickHandler)
local TutorialPolicy = require(_Shared.TutorialPolicy)
local TutorialEvents = require(ServerScriptService.TutorialEvents)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "DayCycleHandler" })

--[[ Tables ]]--
local DayCycleHandler = {
	dependencies = { "DataHandler", "TickHandler", "EconomyHandler", "UpgradeHandler" },
	priority = 60,
}

DayCycleHandler.PhaseChanged = Signal() :: Signal.Signal<Player, GameTypes.DayPhase>
DayCycleHandler.ShiftStarted = Signal() :: Signal.Signal<Player>
DayCycleHandler.ShiftEnded = Signal() :: Signal.Signal<Player>
DayCycleHandler.DayStarted = Signal() :: Signal.Signal<Player, number>

--[[ Private Functions ]]--
type GuestBodySet = { [Model]: boolean }

-- Weak keys let destroyed guest bodies drop out of the set on their own.
local function newGuestBodySet(): GuestBodySet
	return setmetatable({}, { __mode = "k" }) :: any
end

local function getDay(player: Player): any?
	local data = DataHandler:GetData(player)
	return data and data.Session.Day
end

local function copyList(source: any): { string }
	local copy = {}

	for index = 1, #source do
		copy[index] = source[index]
	end

	return copy
end

local function returnLoadedProduce(data: any, station: any): ()
	for ingredientId, amount in station.Loaded or {} do
		if amount > 0 and not Ingredients:IsInfinite(ingredientId) then
			data.Cloud.Pantry[ingredientId] = (data.Cloud.Pantry[ingredientId] or 0) + amount
		end
	end
	station.Loaded = {}
end

local function isStationAvailable(player: Player, station: GameTypes.StationKind): boolean
	local kind = BuildingsConfig.Kinds[station]
	if not kind or not kind.Stat then
		return true
	end

	return UpgradeHandler:HasStat(player, kind.Stat :: any)
end

local function validateRecipes(player: Player, menu: { string }): (boolean, string?)
	for _, recipeId in menu do
		local recipe = Recipes:Get(recipeId)
		if not recipe or not EconomyHandler:IsRecipeUnlocked(player, recipeId) then
			return false, "recipe_locked"
		end

		if not isStationAvailable(player, recipe.station) then
			return false, "station_missing"
		end
	end

	return true, nil
end

--[[ Lifecycle ]]--
function DayCycleHandler.OnInit(self: DayCycleHandler): ()
	self.Machines = {}
	self.Lifetimes = {}
	self.GuestBodies = {}
	self.ClosingChecks = {}
end

function DayCycleHandler.OnStart(self: DayCycleHandler): ()
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:CreateMachine(player)
	end)

	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			self:CreateMachine(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local lifetime = self.Lifetimes[player]
		if lifetime then
			lifetime:Destroy()
		end
		self.Lifetimes[player] = nil
		self.GuestBodies[player] = nil
		self.ClosingChecks[player] = nil
		self.Machines[player] = nil
	end)

	TickHandler.Tick:Connect(function(deltaTime: number)
		self:UpdateMachines(deltaTime)
	end)

	Bus.Day.SelectMenu.OnServerEvent:Connect(function(player: Player, recipeIds: any)
		local menu = Sanitize.IdList(recipeIds, DayCycleConfig.MenuMax)
		if menu then
			self:SelectMenu(player, menu)
		end
	end)

	Bus.Day.Open.OnServerEvent:Connect(function(player: Player)
		self:OpenBakery(player)
	end)

	Bus.Day.Next.OnServerEvent:Connect(function(player: Player)
		self:NextDay(player)
	end)
end

--[[ State Machine ]]--
function DayCycleHandler.CreateMachine(self: DayCycleHandler, player: Player): ()
	if self.Machines[player] then
		return
	end

	local machine = StateMachine.new({
		initialState = "Prep",
		states = {
			Prep = {
				allowedTransitions = { Shift = true, Closing = false, Summary = false },
				onEnter = function()
					self:EnterPrep(player)
				end,
			},
			Shift = {
				allowedTransitions = { Prep = false, Closing = true, Summary = true },
				onEnter = function()
					self:EnterShift(player)
				end,
			},
			Closing = {
				allowedTransitions = { Prep = false, Shift = false, Summary = true },
				onEnter = function()
					self:EnterClosing(player)
				end,
			},
			Summary = {
				allowedTransitions = { Prep = true, Shift = false, Closing = false },
				onEnter = function()
					self:EnterSummary(player)
				end,
			},
		},
		transitions = {
			{
				from = "Shift",
				to = "Closing",
				condition = function()
					local day = getDay(player)
					return day ~= nil and day.EndsAt > 0 and workspace:GetServerTimeNow() >= day.EndsAt
				end,
			},
			{
				from = "Closing",
				to = "Summary",
				condition = function()
					return self:CanFinishClosing(player)
				end,
			},
		},
		errorHandler = function(message: string)
			Logger:Warn(`{player.Name}: {message}`)
		end,
	})

	self.Machines[player] = machine
	local lifetime = Janitor.new()
	lifetime:Add(machine.onStateChange, "Destroy")
	self.Lifetimes[player] = lifetime
	self.GuestBodies[player] = newGuestBodySet()
end

function DayCycleHandler.EnterPrep(self: DayCycleHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local day = data.Session.Day
	-- Keep unfinished work across days without burning it while its owner reads the report.
	local paused = if day.SummaryStartedAt > 0 then workspace:GetServerTimeNow() - day.SummaryStartedAt else 0
	for stationId in data.Session.Stations do
		local station = data.Session.Stations[stationId]
		for _, field in { "PhaseStartedAt", "ReadyAt", "BurnAt", "FuelEndsAt", "HeatPausedAt" } do
			if (station[field] or 0) > 0 then
				station[field] = station[field] + paused
			end
		end
	end
	day.SummaryStartedAt = 0
	-- Removed recipe ids must not leave a returning player with an unopenable bakery.
	if data.Cloud.RecipeCatalogVersion < 1 then
		local menu = {}
		for _, recipeId in copyList(data.Cloud.DayMenu) do
			if
				#menu < DayCycleConfig.MenuMax
				and validateRecipes(player, { recipeId })
				and not table.find(menu, recipeId)
			then
				menu[#menu + 1] = recipeId
			end
		end
		for _, recipeId in { "bread", "sweet_roll", "marshmallow_twist" } do
			if #menu >= DayCycleConfig.MenuMin then
				break
			end
			if not table.find(menu, recipeId) then
				menu[#menu + 1] = recipeId
			end
		end
		data.Cloud.DayMenu = menu
		data.Cloud.RecipeCatalogVersion = 1
	end
	day.Number = data.Cloud.Day
	day.Phase = "Prep"
	day.EndsAt = 0
	day.Menu = copyList(data.Cloud.DayMenu)
	day.NextMenu = {}
	data.Session.Cooking.SelectedRecipeId = nil

	-- A partial idle batch belongs to yesterday. Completed or running work remains collectible.
	for stationId in data.Session.Stations do
		local station = data.Session.Stations[stationId]
		if station.Kind == "Mixer" and station.State == "Idle" then
			returnLoadedProduce(data, station)
		end
	end

	day.Summary.Coins = 0
	day.Summary.XP = 0
	day.Summary.Served = 0
	day.Summary.Lost = 0
	for _, row in DayReportConfig.Rows do
		day.Summary[row.Key] = 0
	end

	self.PhaseChanged:Fire(player, "Prep")
	self.DayStarted:Fire(player, day.Number)
end

function DayCycleHandler.EnterShift(self: DayCycleHandler, player: Player): ()
	local day = getDay(player)
	if not day then
		return
	end

	day.Phase = "Shift"
	local data = DataHandler:GetData(player)
	day.EndsAt = if data and TutorialPolicy.IsActive(data.Cloud)
		then 0
		else workspace:GetServerTimeNow() + DayCycleConfig.ShiftSeconds

	Logger:Info(`{player.Name} opened the bakery, day {day.Number}`)
	self.PhaseChanged:Fire(player, "Shift")
	self.ShiftStarted:Fire(player)
end

function DayCycleHandler.EnterClosing(self: DayCycleHandler, player: Player): ()
	local day = getDay(player)
	if not day then
		return
	end
	day.EndsAt = 0
	day.Phase = "Closing"
	self.ClosingChecks[player] = workspace:GetServerTimeNow() + DayCycleConfig.ClosingCheckSeconds
	self.PhaseChanged:Fire(player, "Closing")
end

-- Waiting includes physical exit walks, without a handler dependency cycle.
function DayCycleHandler.TrackGuestBody(self: DayCycleHandler, player: Player, model: Model): ()
	local bodies = self.GuestBodies[player]
	if bodies then
		bodies[model] = true
	end
end

-- Once back on the public sidewalk, a departing pedestrian no longer occupies the cafe.
function DayCycleHandler.UntrackGuestBody(self: DayCycleHandler, player: Player, model: Model): ()
	local bodies = self.GuestBodies[player]
	if bodies then
		bodies[model] = nil
	end
end

function DayCycleHandler.CanFinishClosing(self: DayCycleHandler, player: Player): boolean
	local now = workspace:GetServerTimeNow()
	if now < (self.ClosingChecks[player] or math.huge) then
		return false
	end
	self.ClosingChecks[player] = now + DayCycleConfig.ClosingCheckSeconds
	local data = DataHandler:GetData(player)
	if not data then
		return false
	end
	for _ in data.Session.Customers do
		return false
	end
	local bodies = self.GuestBodies[player]
	if bodies then
		for model in bodies do
			if model.Parent then
				return false
			end
		end
	end
	return true
end

function DayCycleHandler.EnterSummary(self: DayCycleHandler, player: Player): ()
	local day = getDay(player)
	if not day then
		return
	end

	local completedFullShift = day.Phase == "Closing"
	-- Early closing settles unfinished guests once before publishing the report.
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	for _, customer in data.Session.Customers do
		if customer.State == "Eating" then
			self:AddResult(player, 0, 0, 1, 0)
		else
			self:AddResult(player, 0, -Economy.XPLostCustomer, 0, 1)
		end
	end
	day.EndsAt = 0
	day.NextMenu = copyList(day.Menu)
	if completedFullShift then
		day.Summary.XP = day.Summary.XP + EconomyHandler:AwardXP(player, Economy.XPShiftComplete)
	end

	self.ClosingChecks[player] = nil
	day.SummaryStartedAt = workspace:GetServerTimeNow()
	-- Phase commits the report only after its values and tomorrow's draft exist.
	day.Phase = "Summary"
	Logger:Info(`{player.Name} closed day {day.Number}: {day.Summary.Served} served, {day.Summary.Coins} coins`)
	self.PhaseChanged:Fire(player, "Summary")
	self.ShiftEnded:Fire(player)
	Bus.Day.ShiftEnded:FireClient(player)
end

function DayCycleHandler.GetPhase(_self: DayCycleHandler, player: Player): GameTypes.DayPhase?
	local day = getDay(player)
	return if day then day.Phase else nil
end

function DayCycleHandler.IsShiftActive(self: DayCycleHandler, player: Player): boolean
	local phase = self:GetPhase(player)
	return phase == "Shift" or phase == "Closing"
end

function DayCycleHandler.CanAcceptCustomers(_self: DayCycleHandler, player: Player): boolean
	local day = getDay(player)
	return day ~= nil and DayCycleConfig.CanAcceptCustomers(day.Phase, day.EndsAt, workspace:GetServerTimeNow())
end

function DayCycleHandler.GetShiftProgress(_self: DayCycleHandler, player: Player): number
	local day = getDay(player)
	if not day or day.Phase ~= "Shift" then
		return 0
	end

	return DayCycleConfig.GetShiftProgress(day.EndsAt, workspace:GetServerTimeNow())
end

-- The evening screen edits only tomorrow's draft; today's menu remains immutable.
function DayCycleHandler.SelectMenu(_self: DayCycleHandler, player: Player, menu: { string }): boolean
	local day = getDay(player)
	if not day or day.Phase ~= "Summary" then
		Bus.Progress.ActionFailed:FireClient(player, "not_summary_phase")
		return false
	end

	local valid, reason = validateRecipes(player, menu)
	if not valid then
		Bus.Progress.ActionFailed:FireClient(player, reason :: string)
		return false
	end

	day.NextMenu = menu
	return true
end

function DayCycleHandler.IsOnMenu(_self: DayCycleHandler, player: Player, recipeId: string): boolean
	local day = getDay(player)
	return day ~= nil and DataList.Contains(day.Menu, recipeId)
end

function DayCycleHandler.OpenBakery(self: DayCycleHandler, player: Player): boolean
	local day = getDay(player)
	local machine = self.Machines[player]
	if not day or not machine or day.Phase ~= "Prep" then
		return false
	end

	if #day.Menu < DayCycleConfig.MenuMin then
		Bus.Progress.ActionFailed:FireClient(player, "menu_not_ready")
		return false
	end
	if #day.Menu > DayCycleConfig.MenuMax then
		Bus.Progress.ActionFailed:FireClient(player, "menu_too_large")
		return false
	end

	local valid, reason = validateRecipes(player, copyList(day.Menu))
	if not valid then
		Bus.Progress.ActionFailed:FireClient(player, reason :: string)
		return false
	end

	machine:SetState("Shift")
	return true
end

function DayCycleHandler.EndShift(self: DayCycleHandler, player: Player): boolean
	local machine = self.Machines[player]
	if not machine or machine:GetCurrentState() ~= "Shift" then
		return false
	end

	machine:SetState("Summary")
	return true
end

-- The door prompt opens during Prep, closes during Shift and is disabled by its view in Summary.
function DayCycleHandler.ToggleBakery(self: DayCycleHandler, player: Player): boolean
	local phase = self:GetPhase(player)
	if phase == "Prep" then
		return self:OpenBakery(player)
	end
	if phase ~= "Shift" then
		return false
	end

	return self:EndShift(player)
end

function DayCycleHandler.NextDay(self: DayCycleHandler, player: Player): boolean
	local data = DataHandler:GetData(player)
	local machine = self.Machines[player]
	local day = data and data.Session.Day
	if not data or not machine or not day or day.Phase ~= "Summary" then
		Bus.Progress.ActionFailed:FireClient(player, "not_summary_phase")
		return false
	end

	if #day.NextMenu < DayCycleConfig.MenuMin then
		Bus.Progress.ActionFailed:FireClient(player, "menu_too_small")
		return false
	end
	if #day.NextMenu > DayCycleConfig.MenuMax then
		Bus.Progress.ActionFailed:FireClient(player, "menu_too_large")
		return false
	end

	local nextMenu = copyList(day.NextMenu)
	local valid, reason = validateRecipes(player, nextMenu)
	if not valid then
		Bus.Progress.ActionFailed:FireClient(player, reason :: string)
		return false
	end

	data.Cloud.DayMenu = nextMenu
	data.Cloud.Day = data.Cloud.Day + 1
	TutorialEvents.Action:Fire(player, "NextDay", "")
	machine:SetState("Prep")

	return true
end

-- A server-side tutorial reset pauses the current shift without changing the day FSM.
function DayCycleHandler.HoldTutorialClock(_self: DayCycleHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if data and TutorialPolicy.IsActive(data.Cloud) and data.Session.Day.Phase == "Shift" then
		data.Session.Day.EndsAt = 0
	end
end

-- Releasing tutorial protection starts the clock once, without restarting the guest system.
function DayCycleHandler.ReleaseTutorialClock(_self: DayCycleHandler, player: Player): ()
	local day = getDay(player)
	if day and day.Phase == "Shift" and day.EndsAt == 0 then
		day.EndsAt = workspace:GetServerTimeNow() + DayCycleConfig.ShiftSeconds
	end
end

-- Pays out immediately: the visible summary and wallet cannot drift apart.
function DayCycleHandler.AddResult(
	_self: DayCycleHandler,
	player: Player,
	coins: number,
	xp: number,
	served: number,
	lost: number
): ()
	local day = getDay(player)
	if not day then
		return
	end

	if day.Phase == "Summary" then
		return
	end
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local before = data.Cloud.Cash
	EconomyHandler:AddCash(player, coins)
	day.Summary.Coins = math.round((day.Summary.Coins + data.Cloud.Cash - before) * 100) / 100
	day.Summary.XP = day.Summary.XP + EconomyHandler:AwardXP(player, xp)
	day.Summary.Served = day.Summary.Served + served
	day.Summary.Lost = day.Summary.Lost + lost
end

-- Only accepted server gameplay calls this method; there is no client counter packet.
function DayCycleHandler.RecordStat(_self: DayCycleHandler, player: Player, key: string): ()
	local day = getDay(player)
	if not day or day.Phase == "Summary" then
		return
	end
	for _, row in DayReportConfig.Rows do
		if row.Key == key then
			day.Summary[key] = day.Summary[key] + 1
			return
		end
	end
end

function DayCycleHandler.UpdateMachines(self: DayCycleHandler, deltaTime: number): ()
	for player, machine in self.Machines do
		if player.Parent == Players then
			machine:Update(deltaTime)
		end
	end
end

export type DayCycleHandler = typeof(DayCycleHandler) & {
	Machines: { [Player]: any },
	Lifetimes: { [Player]: any },
	GuestBodies: { [Player]: GuestBodySet },
	ClosingChecks: { [Player]: number },
}

return DayCycleHandler :: DayCycleHandler
