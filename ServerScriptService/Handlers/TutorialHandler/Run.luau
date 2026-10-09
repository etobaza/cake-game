--!strict
-- One player's introduction. Accepted gameplay actions drive the FSM; live state repairs its context.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Analytics = require(script.Parent.Analytics)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local Features = require(ReplicatedStorage.Shared.Tutorial.Features)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Policy = require(ReplicatedStorage.Shared.TutorialPolicy)
local StateMachine = require(ReplicatedStorage.Shared.Libs.StateMachine)

--[[ Tables ]]--
local Run = {}
Run.__index = Run
local Milestones = {
	SelectRecipe = "RecipeSelected",
	Mix = "Mixed",
	Refuel = "FueledOven",
	TakeOrder = "OrderTaken",
	Mopped = "Mopped",
	DisposeBurnt = "DisposedBurnt",
	DisposeDish = "DisposedDish",
	LoadCart = "LoadedCart",
}
local Lessons = { Place = "Display", TakeCart = "Cart", NextDay = "NextDay" }

--[[ Private Functions ]]--
local function mark(self: any, name: string): ()
	local actions = self.Data.Cloud.Tutorial.Actions
	if actions[name] then
		return
	end
	actions[name] = true
	if Policy.IsActive(self.Data.Cloud) or name == "Completed" or name == "Skipped" then
		Analytics.Record(self.Player, name, self.Data.Session.Tutorial.Stage)
	end
end

local function enter(self: any, stage: string): ()
	self.Data.Session.Tutorial.Stage = stage
end

local function finish(self: any, stage: string): ()
	local context = self.Data.Session.Tutorial
	self.Data.Cloud.Tutorial.Status = stage
	context.Protected = false
	if stage == "Completed" then
		context.CompletedAt = workspace:GetServerTimeNow()
	end
	mark(self, stage)
	enter(self, stage)
	self.Release(self.Player)
end

local function serve(self: any, customerId: string): ()
	local context = self.Data.Session.Tutorial
	local customer = self.Data.Session.Customers[customerId]
	if not customer or customerId ~= context.GuestId or not customer.TableId then
		return
	end
	context.TableId = customer.TableId
	context.SeatIndex = customer.SeatIndex or 1
	mark(self, "Served")
	self.Machine:SetState("Clean")
end

--[[ Handling ]]--
function Run.new(player: Player, data: any, release: (Player) -> (), prepareFloor: () -> boolean?): Run
	local self: any = setmetatable({
		Player = player,
		Data = data,
		Release = release,
		PrepareFloor = prepareFloor,
		Janitor = Janitor.new(),
		Machine = nil,
		-- Feature ids owned when the current shift began; nil when joined mid-shift.
		ShiftFeatures = nil,
		-- Whether the sweep's skip-for-live-cooking check already ran.
		SweepJudged = false,
	}, Run)
	local active = Policy.IsActive(data.Cloud)
	data.Session.Tutorial.Protected = active
	self.Machine = StateMachine.new({
		initialState = if Policy.NeedsFloor(data.Cloud)
			then "Sweep"
			elseif active then "Cook"
			else data.Cloud.Tutorial.Status,
		states = {
			Sweep = {
				onEnter = function(): ()
					enter(self, "Sweep")
				end,
			},
			Cook = {
				onEnter = function(): ()
					enter(self, "Cook")
				end,
			},
			Serve = {
				onEnter = function(): ()
					enter(self, "Serve")
				end,
			},
			Clean = {
				onEnter = function(): ()
					enter(self, "Clean")
				end,
			},
			Completed = {
				onEnter = function(): ()
					enter(self, "Completed")
				end,
			},
			Skipped = {
				onEnter = function(): ()
					enter(self, "Skipped")
				end,
			},
		},
	})
	self.Janitor:Add(self.Machine.onStateChange, "Destroy")
	if active then
		mark(self, "Started")
	end
	self:Refresh()
	return self
end

function Run.Refresh(self: Run): ()
	if not Policy.IsActive(self.Data.Cloud) then
		return
	end
	local session = self.Data.Session
	local context = session.Tutorial
	if context.Stage == "Sweep" and session.Day.Phase ~= "Summary" then
		-- Restarting the tutorial must not send an existing batch or dish to the trash. That is
		-- judged once, when the bakery is first ready: a recipe chosen during the sweep afterwards
		-- does not skip it.
		local cooking = false
		if not self.SweepJudged then
			cooking = session.Cooking.SelectedRecipeId ~= nil
			for _, station in session.Stations do
				cooking = cooking or station.State ~= "Idle"
			end
			for _, item in session.Hands do
				cooking = cooking or item.Kind == "Dish" or item.Kind == "Dough"
			end
		end
		local available = if cooking then false else self.PrepareFloor()
		if available ~= nil then
			self.SweepJudged = true
		end
		if available == false and not cooking then
			print(`[TutorialHandler] {self.Player.Name}: no tutorial spill could be placed; skipping the sweep`)
		end
		local held = session.Hands[1]
		local holdingBroom = held and held.Kind == "Tool" and held.Id == Buildings.Kinds.Broom.ToolId
		local hasSpills = false
		for _ in session.Spills do
			hasSpills = true
			break
		end
		local cleaned = self.Data.Cloud.Tutorial.Actions.Mopped and not hasSpills and not holdingBroom
		if available == false or cleaned then
			mark(self, "PreparedFloor")
			self.Machine:SetState("Cook")
		else
			return
		end
	end
	local customer = session.Customers[context.GuestId]
	if customer then
		if customer.State == "Waiting" or customer.State == "Eating" then
			mark(self, "OrderTaken")
		end
		if context.TableId ~= (customer.TableId or "") then
			context.TableId = customer.TableId or ""
		end
		if context.SeatIndex ~= (customer.SeatIndex or 0) then
			context.SeatIndex = customer.SeatIndex or 0
		end
	end
	if session.Day.Phase == "Summary" then
		if context.GuestId ~= "" then
			context.GuestId = ""
		end
		if context.TableId ~= "" then
			context.TableId = ""
		end
		if context.SeatIndex ~= 0 then
			context.SeatIndex = 0
		end
		-- A new preparation period clears guests and places. Keep learned actions,
		-- then reconstruct a feasible order instead of pointing at yesterday's seat.
		if context.Stage ~= "Cook" then
			self.Machine:SetState("Cook")
		end
		return
	end
	local recipeId = Policy.Recipe(session) or ""
	if context.RecipeId ~= recipeId then
		context.RecipeId = recipeId
	end
	if context.Stage ~= "Cook" then
		return
	end
	for _, held in session.Hands do
		if held.Kind ~= "Dish" then
			continue
		end
		mark(self, "CollectedDish")
		self.Machine:SetState("Serve")
		return
	end
	for _ in session.Display do
		mark(self, "CollectedDish")
		self.Machine:SetState("Serve")
		return
	end
end

function Run.Action(self: Run, action: string, id: string): ()
	local saved = self.Data.Cloud.Tutorial
	local station = self.Data.Session.Stations[id]
	if
		not Policy.IsActive(self.Data.Cloud)
		and station
		and station.Kind == "Oven"
		and (action == "Load" or action == "Refuel")
	then
		self.Data.Session.Tutorial.OvenLesson = true
	end
	for _, feature in Config.Features do
		if Features.Matches(feature, action, id) and not saved.Actions[`Use:{feature.id}`] then
			saved.Actions[`Use:{feature.id}`] = true
		end
	end
	local milestone = Milestones[action]
	if milestone then
		mark(self, milestone)
	end
	local lesson = Lessons[action]
	if lesson and not saved.Lessons[lesson] then
		saved.Lessons[lesson] = true
	end
	if action == "Harvest" then
		saved.Actions[`Harvest:{id}`] = true
		-- One harvest teaches the routine; later sources are reached through cooking guidance.
		if not saved.Lessons.Garden then
			saved.Lessons.Garden = true
		end
	end
	if action == "Tend" then
		saved.Actions[`Care:{id}`] = true
	end
	if action == "ReturnTool" and id == Buildings.Kinds.Broom.ToolId and saved.Actions.Mopped then
		saved.Lessons.Floor = true
	end
	if action == "Collect" then
		local held = self.Data.Session.Hands[1]
		if held and held.Kind == "Dish" then
			mark(self, "CollectedDish")
		end
		if held and held.Kind == "Dish" and station and station.Kind == "Oven" then
			mark(self, "CollectedOvenDish")
		end
		if held and held.Kind == "Dough" then
			mark(self, "CollectedDough")
		end
	end
	if not Policy.IsActive(self.Data.Cloud) then
		return
	end
	if action == "Serve" then
		serve(self, id)
	end
	if action == "CleanTable" then
		local context = self.Data.Session.Tutorial
		local tableState = self.Data.Session.Tables[id]
		local seat = tableState and tableState.Seats[context.SeatIndex]
		if context.Stage == "Clean" and context.TableId == id and seat and not seat.CustomerId and not seat.Dirty then
			mark(self, "CleanedTable")
			self:Finish("Completed")
		end
	end
	self:Refresh()
end

-- Only features owned for the whole shift can be judged unused at its end.
function Run.ShiftStarted(self: Run): ()
	local cloud = self.Data.Cloud
	local owned = {}
	for _, feature in Config.Features do
		if feature.task and Features.Used(cloud, feature) and not cloud.Tutorial.Actions[`Use:{feature.id}`] then
			cloud.Tutorial.Actions[`Use:{feature.id}`] = true
		end
		if Features.Owned(cloud, feature) then
			owned[feature.id] = true
		end
	end
	self.ShiftFeatures = owned
end

-- The first unused shift makes a feature's guide due; a second unused shift retires it.
function Run.ShiftEnded(self: Run): ()
	local owned = self.ShiftFeatures
	self.ShiftFeatures = nil
	if not owned then
		return
	end
	local cloud = self.Data.Cloud
	local lessons = cloud.Tutorial.Lessons
	for _, feature in Config.Features do
		if not owned[feature.id] or Features.Used(cloud, feature) or lessons[`Feature:{feature.id}`] then
			continue
		end
		if lessons[`Due:{feature.id}`] then
			lessons[`Feature:{feature.id}`] = true
		else
			lessons[`Due:{feature.id}`] = true
		end
	end
end

function Run.Finish(self: Run, status: string): ()
	if not Policy.IsActive(self.Data.Cloud) then
		return
	end
	finish(self, status)
	self.Machine:SetState(status)
end

function Run.Destroy(self: Run): ()
	self.Janitor:Destroy()
end

export type Run = typeof(setmetatable(
	{} :: {
		Player: Player,
		Data: any,
		Release: (Player) -> (),
		PrepareFloor: () -> boolean?,
		Janitor: any,
		Machine: any,
		ShiftFeatures: { [string]: boolean }?,
		SweepJudged: boolean,
	},
	Run
))

return Run
