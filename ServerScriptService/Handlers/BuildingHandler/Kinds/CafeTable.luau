--!strict
-- Cafe table FSM with independent dining places. A dirty place never evicts its occupied neighbour.
-- Customer ids reserve seats before their bodies arrive; only cleaning makes a used seat available.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.TableMenus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local BaseHandler = require(ServerScriptService.Handlers.BaseHandler)
local Bus = require(ReplicatedStorage.Shared.Bus)
local FoodConfig = require(ReplicatedStorage.Shared.Configs.FoodPresentation)

--[[ Tables ]]--
local CafeTable = {}

--[[ Private Functions ]]--
local function emitCleaning(building: any, index: number): ()
	local anchors = BaseHandler.Template:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(building.Id)
	local name = FoodConfig.SurfaceAttachment .. (if index == 1 then "" else tostring(index))
	local surface = anchor and anchor:FindFirstChild(name)
	local transform = BaseHandler:GetTransform(building.Player)
	if not surface or not surface:IsA("Attachment") or not transform then
		return
	end
	Bus.VFX.Burst:Fire(
		"Cleaning",
		building.Part,
		transform * surface.WorldCFrame,
		building.Player.UserId,
		workspace:GetServerTimeNow()
	)
end

local function getStateName(state: any): string
	local occupied, dirty = false, false
	for _, seat in state.Seats do
		occupied = occupied or seat.CustomerId ~= nil
		dirty = dirty or seat.Dirty
	end
	state.Dirty = dirty
	return if occupied then "Occupied" elseif dirty then "Dirty" else "Free"
end

local function refresh(building: any): ()
	local name = getStateName(building.State)
	if building:GetState() ~= name then
		building:SetState(name)
	end
end

local function customerSeat(building: any, customerId: string): any?
	for index = 1, Config.SeatCount do
		local seat = building.State.Seats[index]
		if seat.CustomerId == customerId then
			return seat
		end
	end
	return nil
end

--[[ Handling ]]--
function CafeTable.EnsureState(building: any): any?
	local data = DataHandler:GetData(building.Player)
	local tables = data and data.Session[building.Definition.StateField]
	if not tables then
		return nil
	end
	if not tables[building.Id] then
		local seats = {}
		for index = 1, Config.SeatCount do
			seats[index] = { Dirty = false, MenuHidden = false, Served = {} }
		end
		tables[building.Id] = { Dirty = false, Seats = seats }
	end
	return tables[building.Id]
end

function CafeTable.BuildConfig(building: any): any
	return {
		initialState = getStateName(building.State),
		params = { Now = 0 },
		states = {
			Free = { allowedTransitions = { Occupied = true } },
			Occupied = { allowedTransitions = { Dirty = true, Free = true } },
			Dirty = { allowedTransitions = { Free = true, Occupied = true } },
		},
	}
end

function CafeTable.FindFreeSeat(building: any): number?
	for index = 1, Config.SeatCount do
		local seat = building.State.Seats[index]
		local physical = building.Part:FindFirstChild(`{Config.SeatName}{index}`)
		if not seat.CustomerId and not seat.Dirty and physical and physical:IsA("Seat") then
			return index
		end
	end
	return nil
end

function CafeTable.Occupy(building: any, customerId: string): number?
	if customerSeat(building, customerId) then
		return nil
	end
	local index = CafeTable.FindFreeSeat(building)
	if not index then
		return nil
	end
	building.State.Seats[index].CustomerId = customerId
	refresh(building)
	return index
end

function CafeTable.HasCustomer(building: any, customerId: string): boolean
	return customerSeat(building, customerId) ~= nil
end

function CafeTable.ServeMenu(building: any, customerId: string, recipeId: string): ()
	local seat = customerSeat(building, customerId)
	if not seat then
		return
	end
	seat.MenuHidden = true
	seat.Served[#seat.Served + 1] = recipeId
end

function CafeTable.TakeOrder(building: any, customerId: string): ()
	local seat = customerSeat(building, customerId)
	if seat then
		seat.MenuHidden = true
	end
end

function CafeTable.Release(building: any, customerId: string): ()
	local seat = customerSeat(building, customerId)
	if not seat then
		return
	end
	seat.CustomerId = nil
	seat.Dirty = true
	seat.MenuHidden = true
	seat.Served = {}
	refresh(building)
end

function CafeTable.Clean(building: any): boolean
	if not building.State.Dirty then
		return false
	end
	for index = 1, Config.SeatCount do
		local seat = building.State.Seats[index]
		if not seat.Dirty then
			continue
		end
		emitCleaning(building, index)
		seat.Dirty = false
		seat.MenuHidden = false
		seat.Served = {}
	end
	refresh(building)
	return true
end

-- Closing already releases guests individually. Preserve every dirty place into the next prep.
function CafeTable.StartDay(building: any): ()
	for index = 1, Config.SeatCount do
		local seat = building.State.Seats[index]
		if seat.CustomerId then
			CafeTable.Release(building, seat.CustomerId)
		end
	end
end

return CafeTable
