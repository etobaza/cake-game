--!strict
-- One player's introduction. Accepted gameplay actions drive the FSM; live state repairs its context.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Analytics = require(script.Parent.Analytics)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
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
function Run.new(player: Player, data: any, release: (Player) -> ()): Run
	local self: any =
		setmetatable({ Player = player, Data = data, Release = release, Janitor = Janitor.new(), Machine = nil }, Run)
	local active = Policy.IsActive(data.Cloud)
	data.Session.Tutorial.Protected = active
	self.Machine = StateMachine.new({
		initialState = if active then "Cook" else data.Cloud.Tutorial.Status,
		states = {
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
	{} :: { Player: Player, Data: any, Release: (Player) -> (), Janitor: any, Machine: any },
	Run
))

return Run
