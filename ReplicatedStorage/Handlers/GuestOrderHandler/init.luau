--!strict
-- Speech bubbles over the local player's seated guests, mirroring Session.Customers: what each guest
-- ordered, their seat number and how much patience is left. Other bakeries' guests stay bare.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Base = require(_Shared.Configs.Base)
local Bubble = require(script.Bubble)
local Config = require(_Shared.Configs.Orders)
local DataClient = require(_Handlers.DataHandlerClient)
local Guests = require(_Shared.Configs.Guests)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local OrderHandler = require(_Handlers.OrderHandler)
local UIHandler = require(_Handlers.UIHandler)
local World = require(_Shared.World)

--[[ Tables ]]--
local GuestOrderHandler = {
	dependencies = { "DataClient", "UIHandler", "OrderHandler" },
}

--[[ Private Functions ]]--
local function findGuests(userId: number): Instance?
	local bakeries = World.Bakeries()
	if not bakeries then
		return nil
	end
	for _, bakery in bakeries:GetChildren() do
		if bakery:GetAttribute(Base.OwnerAttribute) == userId then
			return bakery:FindFirstChild(Guests.FolderName)
		end
	end
	return nil
end

--[[ Handling ]]--
function GuestOrderHandler.OnStart(self: GuestOrderHandler): ()
	self.Janitor = Janitor.new()
	self.Bubbles = {}
	self.Accumulator = 0
	self.UserId = Players.LocalPlayer.UserId
	local order = UIHandler:GetHud("Order")
	local bar = order:FindFirstChild("Bar", true)
	assert(bar and bar:IsA("CanvasGroup"), "[GuestOrderHandler] Order HUD has no Bar CanvasGroup")
	self.BarTemplate = bar:Clone()
	self.Janitor:Add(self.BarTemplate, "Destroy")
	self.Janitor:Add(function(): ()
		for customerId in self.Bubbles do
			self:Remove(customerId)
		end
	end, true)

	DataClient:WaitForData()
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Customers" }, function(): ()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
	-- Patience and the choosing dots are timestamp-derived; models stream in on their own schedule.
	self.Janitor:Add(
		RunService.Heartbeat:Connect(function(deltaTime: number): ()
			self.Accumulator += deltaTime
			if self.Accumulator < Config.RefreshInterval then
				return
			end
			self.Accumulator %= Config.RefreshInterval
			self:Refresh()
		end),
		"Disconnect"
	)
	self:Refresh()
end

function GuestOrderHandler.Remove(self: GuestOrderHandler, customerId: string): ()
	local bubble = self.Bubbles[customerId]
	if bubble then
		bubble:Destroy()
		self.Bubbles[customerId] = nil
	end
end

function GuestOrderHandler.Refresh(self: GuestOrderHandler): ()
	local customers = DataClient:GetData({ "Customers" }, "Session") or {}
	local folder = findGuests(self.UserId)
	local now = workspace:GetServerTimeNow()
	local shown: { [string]: boolean } = {}

	for customerId, customer in customers do
		if customer.Kind == "Display" or not Config.Bubble.States[customer.State] then
			continue
		end
		local model = folder and folder:FindFirstChild(customerId)
		local head = model and model:FindFirstChild("Head")
		if not model or not model:IsA("Model") or not head or not head:IsA("BasePart") then
			continue
		end

		local bubble = self.Bubbles[customerId]
		-- A guest model replaced by streaming gets a fresh bubble on the new body.
		if bubble and bubble.Model ~= model then
			self:Remove(customerId)
		end
		if not self.Bubbles[customerId] then
			self.Bubbles[customerId] = Bubble.new(model, head, self.BarTemplate)
		end
		shown[customerId] = true

		local remaining = if customer.TutorialProtected
			then 1
			else math.clamp((customer.PatienceEndsAt - now) / math.max(customer.Patience, 1), 0, 1)
		self.Bubbles[customerId]:Show({
			State = customer.State,
			Orders = customer.Orders or {},
			Seat = if customer.TableId then OrderHandler.SeatLabel(customer.TableId, customer.SeatIndex) else nil,
			Remaining = remaining,
			Now = now,
		})
	end

	for customerId in self.Bubbles do
		if not shown[customerId] then
			self:Remove(customerId)
		end
	end
end

function GuestOrderHandler.Destroy(self: GuestOrderHandler): ()
	self.Janitor:Destroy()
end

export type GuestOrderHandler = typeof(GuestOrderHandler) & {
	Janitor: any,
	Bubbles: { [string]: Bubble.Bubble },
	BarTemplate: CanvasGroup,
	Accumulator: number,
	UserId: number,
}

return GuestOrderHandler :: GuestOrderHandler
