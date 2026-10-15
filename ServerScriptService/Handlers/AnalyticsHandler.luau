--!strict
-- Creator Dashboard analytics: coin economy, the introduction's onboarding funnel, day, store,
-- first-session and days-finished funnels, level and day progression, and per-shift results. It
-- only observes other handlers' signals; it never gates gameplay or rewards.

--[[ Services ]]--
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local AnalyticsConfig = require(ReplicatedStorage.Shared.Configs.Analytics)
local CustomerHandler = require(_Handlers.CustomerHandler)
local DataHandler = require(_Handlers.DataHandler)
local DayCycleHandler = require(_Handlers.DayCycleHandler)
local EconomyHandler = require(_Handlers.EconomyHandler)
local LoggerUtil = require(ReplicatedStorage.Shared.Libs.Logger)
local Products = require(ReplicatedStorage.Shared.Configs.Registries.Products)
local PurchaseHandler = require(_Handlers.PurchaseHandler)
local TutorialEvents = require(ServerScriptService.TutorialEvents)

--[[ Types ]]--
type FunnelRun = { Id: string, Step: number }
type FirstSessionRun = { Id: string, Step: number, Outcome: string, Upgraded: boolean }
type PlayerState = {
	Day: FunnelRun?,
	-- One open store funnel per product: a second prompt restarts it.
	Store: { [number]: FunnelRun },
	-- Opened when the introduction ends; it lasts until the player leaves.
	FirstSession: FirstSessionRun?,
	Days: FunnelRun,
}

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "AnalyticsHandler" })
local DayFunnel = AnalyticsConfig.Funnels.Day
local StoreFunnel = AnalyticsConfig.Funnels.Store
local FirstSessionFunnel = AnalyticsConfig.Funnels.FirstSession
local DaysFunnel = AnalyticsConfig.Funnels.Days
local Onboarding = AnalyticsConfig.Onboarding

--[[ Tables ]]--
local AnalyticsHandler = {
	dependencies = { "DataHandler", "EconomyHandler", "DayCycleHandler", "CustomerHandler", "PurchaseHandler" },
	priority = 0,
	States = {} :: { [Player]: PlayerState },
}

--[[ Private Functions ]]--
-- Studio sessions would pollute live dashboards, so they only print what would be sent.
local function send(label: string, callback: () -> ()): ()
	if RunService:IsStudio() then
		if AnalyticsConfig.PrintInStudio then
			Logger:Debug(label)
		end
		return
	end

	-- Typed as string? so pcall's second return carries the error message.
	local ok, message = pcall(function(): string?
		callback()
		return nil
	end)
	if not ok then
		Logger:Warn(`{label}: {message}`)
	end
end

local function fields(field01: string?, field02: string?): { [string]: string }?
	if not field01 then
		return nil
	end
	local keys = Enum.AnalyticsCustomFieldKeys
	local result = { [keys.CustomField01.Name] = field01 }
	if field02 then
		result[keys.CustomField02.Name] = field02
	end
	return result
end

-- Low-cardinality day label for custom fields, so dashboards can split early and late players.
local function dayBucket(day: number): string
	for _, bucket in AnalyticsConfig.DayBuckets do
		if day <= bucket.MaxDay then
			return bucket.Label
		end
	end
	return AnalyticsConfig.LateDayLabel
end

local function getDay(player: Player): number
	local data = DataHandler:GetData(player)
	return if data then data.Cloud.Day else 1
end

local function newRun(): FunnelRun
	return { Id = HttpService:GenerateGUID(false), Step = 0 }
end

-- The days run spans sessions, so its id is the player's own.
local function newState(player: Player): PlayerState
	return { Day = nil, Store = {}, FirstSession = nil, Days = { Id = tostring(player.UserId), Step = 0 } }
end

-- Funnel steps only move forward: a repeated or late step is dropped instead of muddying the funnel.
local function step(player: Player, funnel: string, run: FunnelRun, index: number, name: string, field01: string?): ()
	if index <= run.Step then
		return
	end
	run.Step = index
	send(`Funnel {funnel} {index} {name} {field01 or "-"}`, function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, run.Id, index, name, fields(field01))
	end)
end

--[[ Handling ]]--
function AnalyticsHandler.OnStart(self: AnalyticsHandler): ()
	for _, player in Players:GetPlayers() do
		self.States[player] = newState(player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		self.States[player] = newState(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self.States[player] = nil
	end)

	EconomyHandler.CashChanged:Connect(function(player, flow, amount, balance, reason, itemId)
		self:LogCash(player, flow, amount, balance, reason, itemId)
	end)
	EconomyHandler.LevelUp:Connect(function(player: Player, level: number)
		self:LogProgression(player, "Level", level - 1)
	end)

	DayCycleHandler.DayStarted:Connect(function(player: Player)
		self:DayStep(player, "Prep", true)
	end)
	DayCycleHandler.ShiftStarted:Connect(function(player: Player)
		self:DayStep(player, "Opened")
		self:FirstSessionStep(player, "SecondShiftOpened")
	end)
	CustomerHandler.DishSold:Connect(function(player: Player)
		self:DayStep(player, "FirstSale")
	end)
	DayCycleHandler.ShiftEnded:Connect(function(player: Player)
		self:DayStep(player, "Closed")
		-- Only the run's next step counts, so at most one of these applies.
		self:FirstSessionStep(player, "FirstShiftClosed")
		self:FirstSessionStep(player, "SecondShiftClosed")
		self:LogShift(player)
	end)

	TutorialEvents.Action:Connect(function(player: Player, action: string, id: string)
		if action == "NextDay" then
			self:DayStep(player, "NextDay")
			self:FirstSessionStep(player, "NextDay")
		elseif action == "BuyUpgrade" then
			self:LogFirstSessionUpgrade(player, id)
		end
		local event = AnalyticsConfig.ActionEvents[action]
		if event then
			self:LogCustom(player, event, 1, dayBucket(getDay(player)))
		end
	end)
	TutorialEvents.Milestone:Connect(function(player: Player, name: string, stage: string)
		self:OnboardingStep(player, name, stage)
		if name == "Skipped" then
			self:LogCustom(player, Onboarding.SkippedEvent, 1, stage)
		end
		if name == "Completed" or name == "Skipped" then
			self:StartFirstSession(player, name)
		end
	end)

	PurchaseHandler.PurchasePrompted:Connect(function(player: Player, productId: number)
		self:StoreStep(player, productId, "Prompted")
	end)
	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number, isGift: boolean)
		if not isGift then
			self:StoreStep(player, productId, "Purchased")
		end
	end)
end

function AnalyticsHandler.LogCash(
	_self: AnalyticsHandler,
	player: Player,
	flow: EconomyHandler.CashFlow,
	amount: number,
	balance: number,
	reason: EconomyHandler.CashReason,
	itemId: string?
): ()
	if reason == "Admin" or amount <= 0 then
		return
	end
	local flowType = if flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	send(`Economy {flow} {amount} {reason} {itemId or "-"} -> {balance}`, function()
		AnalyticsService:LogEconomyEvent(player, flowType, AnalyticsConfig.Currency, amount, balance, reason, itemId)
	end)
end

function AnalyticsHandler.LogProgression(_self: AnalyticsHandler, player: Player, path: string, level: number): ()
	if level < 1 then
		return
	end
	send(`Progression {path} {level}`, function()
		AnalyticsService:LogProgressionEvent(
			player,
			path,
			Enum.AnalyticsProgressionType.Complete,
			level,
			`{path} {level}`
		)
	end)
end

function AnalyticsHandler.LogCustom(
	_self: AnalyticsHandler,
	player: Player,
	event: string,
	value: number,
	field01: string?,
	field02: string?
): ()
	send(`Custom {event} {value} {field01 or "-"} {field02 or "-"}`, function()
		AnalyticsService:LogCustomEvent(player, event, value, fields(field01, field02))
	end)
end

-- Steps of the recurring day funnel. `restart` opens a new run; a player who joins mid-day starts one
-- at their first step, so later steps are still counted.
function AnalyticsHandler.DayStep(self: AnalyticsHandler, player: Player, name: string, restart: boolean?): ()
	local state = self.States[player]
	local index = table.find(DayFunnel.Steps, name)
	if not state or not index then
		return
	end
	if restart or not state.Day then
		state.Day = newRun()
	end
	step(player, DayFunnel.Name, state.Day :: FunnelRun, index, name)
end

function AnalyticsHandler.StoreStep(self: AnalyticsHandler, player: Player, productId: number, name: string): ()
	local state = self.States[player]
	local index = table.find(StoreFunnel.Steps, name)
	local product = Products:GetByProductId(productId)
	if not state or not index or not product then
		return
	end
	if index == 1 then
		state.Store[productId] = newRun()
	end
	local run = state.Store[productId]
	if not run then
		return
	end
	step(player, StoreFunnel.Name, run, index, name, product.id)
	if index == #StoreFunnel.Steps then
		state.Store[productId] = nil
	end
end

-- The one-time onboarding funnel moves through done steps only: a step is logged once every
-- earlier one is done (saved tutorial actions), then any later step done early follows at once.
function AnalyticsHandler.OnboardingStep(_self: AnalyticsHandler, player: Player, name: string, stage: string): ()
	local data = DataHandler:GetData(player)
	local index = table.find(Onboarding.Steps, name)
	if not data or not index then
		return
	end
	local actions = data.Cloud.Tutorial.Actions
	for earlier = 1, index - 1 do
		local earlierName = Onboarding.Steps[earlier]
		local skipped = stage ~= "Sweep" and Onboarding.SweepSteps[earlierName] == true
		if not actions[earlierName] and not skipped then
			return
		end
	end

	for current = index, #Onboarding.Steps do
		local currentName = Onboarding.Steps[current]
		if current > index and not actions[currentName] then
			break
		end
		send(`Onboarding {current} {currentName}`, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, current, currentName)
		end)
	end
end

function AnalyticsHandler.StartFirstSession(self: AnalyticsHandler, player: Player, outcome: string): ()
	local state = self.States[player]
	if not state then
		return
	end
	state.FirstSession = { Id = HttpService:GenerateGUID(false), Step = 0, Outcome = outcome, Upgraded = false }
	self:FirstSessionStep(player, FirstSessionFunnel.Steps[1])
end

-- A shift opened before the first close (an introduction skipped in the morning) or a third day
-- never lands on a later step, because only the run's next step counts.
function AnalyticsHandler.FirstSessionStep(self: AnalyticsHandler, player: Player, name: string): ()
	local state = self.States[player]
	local run = state and state.FirstSession
	if not run or FirstSessionFunnel.Steps[run.Step + 1] ~= name then
		return
	end
	step(player, FirstSessionFunnel.Name, run, run.Step + 1, name, run.Outcome)
end

-- The run's step tells when it was bought: which day, and before or after closing.
function AnalyticsHandler.LogFirstSessionUpgrade(self: AnalyticsHandler, player: Player, upgradeId: string): ()
	local state = self.States[player]
	local run = state and state.FirstSession
	if not run or run.Upgraded then
		return
	end
	run.Upgraded = true
	self:LogCustom(player, FirstSessionFunnel.UpgradeEvent, 1, FirstSessionFunnel.Steps[run.Step], upgradeId)
end

function AnalyticsHandler.DaysStep(self: AnalyticsHandler, player: Player, day: number): ()
	local state = self.States[player]
	if not state or day < 1 or day > DaysFunnel.MaxDay then
		return
	end
	step(player, DaysFunnel.Name, state.Days, day, `Day{day}`)
end

-- One event per day total: what the shift earned, how many guests were served and how many left.
function AnalyticsHandler.LogShift(self: AnalyticsHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local day = data.Session.Day
	self:LogProgression(player, "Day", day.Number)
	self:DaysStep(player, day.Number)

	local bucket = dayBucket(day.Number)
	local summary = day.Summary
	self:LogCustom(player, "ShiftCoins", summary.Coins, bucket)
	self:LogCustom(player, "ShiftServed", summary.Served, bucket)
	self:LogCustom(player, "ShiftLost", summary.Lost, bucket)
end

export type AnalyticsHandler = typeof(AnalyticsHandler)

return AnalyticsHandler
