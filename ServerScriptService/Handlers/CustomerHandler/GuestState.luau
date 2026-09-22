--!strict
-- One guest's lifecycle. The shared server tick advances it; data is the replicated mirror.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local DayCycle = require(ReplicatedStorage.Shared.Configs.DayCycle)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Orders = require(ReplicatedStorage.Shared.Configs.Orders)
local StateMachine = require(ReplicatedStorage.Shared.Libs.StateMachine)

--[[ Tables ]]--
local GuestState = {}
GuestState.__index = GuestState

--[[ Handling ]]--
function GuestState.new(customer: any, onReady: () -> (), onFinish: (boolean) -> ()): GuestState
	local self =
		setmetatable({ Janitor = Janitor.new(), Now = workspace:GetServerTimeNow(), Machine = nil :: any }, GuestState)
	local function enter(name: string): ()
		customer.State = name
	end
	local function finish(served: boolean): ()
		self.Machine:SetState("Leaving")
		onFinish(served)
	end
	local function expire(): ()
		if not customer.TutorialProtected and self.Now >= customer.PatienceEndsAt then
			finish(false)
		end
	end
	self.Machine = StateMachine.new({
		initialState = customer.State,
		states = {
			Queued = {
				onEnter = function(): ()
					enter("Queued")
				end,
				onUpdate = expire,
			},
			Arriving = {
				onEnter = function(): ()
					enter("Arriving")
				end,
				onUpdate = expire,
			},
			Browsing = {
				onEnter = function(): ()
					enter("Browsing")
				end,
			},
			Shopping = {
				onEnter = function(): ()
					enter("Shopping")
				end,
				onUpdate = expire,
			},
			Purchasing = {
				onEnter = function(): ()
					enter("Purchasing")
				end,
			},
			Adopting = {
				onEnter = function(): ()
					enter("Adopting")
				end,
			},
			Choosing = {
				onEnter = function(): ()
					customer.ChoosingEndsAt = self.Now + math.random(Orders.ChooseMinSeconds, Orders.ChooseMaxSeconds)
					customer.PatienceEndsAt = 0
					enter("Choosing")
				end,
				onUpdate = function(): ()
					if self.Now >= customer.ChoosingEndsAt then
						self:TakeOrder()
					end
				end,
			},
			Waiting = {
				onEnter = function(): ()
					customer.PatienceEndsAt = self.Now + customer.Patience
					customer.OrderStartedAt = self.Now
					customer.ChoosingEndsAt = 0
					enter("Waiting")
					onReady()
				end,
				onUpdate = expire,
			},
			Eating = {
				onEnter = function(): ()
					customer.EatEndsAt = self.Now + DayCycle.EatSeconds
					enter("Eating")
				end,
				onUpdate = function(): ()
					if self.Now >= customer.EatEndsAt then
						finish(true)
					end
				end,
			},
			Leaving = {
				onEnter = function(): ()
					enter("Leaving")
				end,
			},
		},
	})
	self.Janitor:Add(self.Machine.onStateChange, "Destroy")
	return self
end

function GuestState.Seat(self: GuestState): ()
	if self.Machine:GetCurrentState() == "Queued" then
		self.Machine:SetState("Arriving")
	end
end

function GuestState.Arrive(self: GuestState): ()
	if self.Machine:GetCurrentState() ~= "Arriving" then
		return
	end
	self.Now = workspace:GetServerTimeNow()
	self.Machine:SetState("Choosing")
end

function GuestState.TakeOrder(self: GuestState): boolean
	if self.Machine:GetCurrentState() ~= "Choosing" then
		return false
	end
	self.Now = workspace:GetServerTimeNow()
	self.Machine:SetState("Waiting")
	return true
end

-- Takeaway visitors have no menu order, patience bar or eating phase.
function GuestState.Browse(self: GuestState): ()
	if self.Machine:GetCurrentState() == "Arriving" then
		self.Machine:SetState("Browsing")
	end
end

function GuestState.Shop(self: GuestState): ()
	if self.Machine:GetCurrentState() == "Browsing" then
		self.Machine:SetState("Shopping")
	end
end

function GuestState.Purchase(self: GuestState): ()
	if self.Machine:GetCurrentState() == "Shopping" then
		self.Machine:SetState("Purchasing")
	end
end

function GuestState.Adopt(self: GuestState): ()
	if self.Machine:GetCurrentState() == "Browsing" then
		self.Machine:SetState("Adopting")
	end
end

function GuestState.Eat(self: GuestState): ()
	if self.Machine:GetCurrentState() ~= "Waiting" then
		return
	end
	self.Now = workspace:GetServerTimeNow()
	self.Machine:SetState("Eating")
end

function GuestState.Update(self: GuestState, now: number): ()
	self.Now = now
	self.Machine:Update(0)
end

function GuestState.Destroy(self: GuestState): ()
	self.Janitor:Destroy()
end

export type GuestState = typeof(setmetatable({} :: { Janitor: any, Now: number, Machine: any }, GuestState))

return GuestState
