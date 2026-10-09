--!strict
-- Prompt view of a shared cafe table. Each dining place has its own prompt target
-- (Context.Seat): Take order and Serve name that one guest. Serving with any dish is allowed, so
-- the server can say the guest wanted something else. The table part itself keeps cleaning, which
-- clears dirty places while another guest may still be ordering or eating.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local BuildingsConfig = require(_Shared.Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataList = require(_Shared.DataList)
local GuestOrders = require(_Shared.GuestOrders)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local Tints = require(script.Parent.Tints)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local CafeTable = {}

--[[ Private Functions ]]--
local function DescribeSeat(context: Types.Context, entry: any, seat: number): Types.PromptState
	local place = entry.Seats and entry.Seats[seat]
	local customerId = place and place.CustomerId
	local customers = context.Session("Customers")
	local customer = customerId and customers and customers[customerId]
	if not customer then
		return { Label = "Free seat" }
	end
	local guest = `Guest {GuestOrders.SeatLabel(context.PropId, seat)}`
	if customer.State == "Choosing" then
		local id = customerId
		return {
			Label = guest,
			Action = "Take order",
			Tint = Tints.Guest,
			Fire = function()
				Bus.Cafe.TakeOrder:Fire(id)
			end,
		}
	end
	if customer.State ~= "Waiting" then
		return { Label = `{guest}: {customer.State}`, Tint = Tints.Guest }
	end

	local held = context.Held()
	local rawRecipe = if held and held.Kind == "Dough" then Recipes:Get(held.Id) else nil
	-- Any dish (or an unbaked oven dough) can be offered: the server explains a wrong or raw one.
	local canAttemptServe = held and (held.Kind == "Dish" or (rawRecipe and rawRecipe.station == "Oven"))
	local wants = `Wants {GuestOrders.DishNames(customer)}`
	if not canAttemptServe then
		return { Label = wants, Tint = Tints.Guest }
	end
	local matches = held.Kind == "Dish" and DataList.Contains(customer.Orders, held.Id)
	local id = customerId
	return {
		Label = if matches then guest else wants,
		Action = "Serve",
		Tint = if matches then Tints.Guest else Tints.Bad,
		Fire = function()
			Bus.Cafe.Serve:Fire(id)
		end,
	}
end

--[[ Handling ]]--
function CafeTable.Describe(context: Types.Context): Types.PromptState
	local kind = BuildingsConfig.Kinds[context.Kind]
	local tables = context.Session(kind.StateField :: string)
	local entry = tables and tables[context.PropId]
	if not entry then
		return { Label = kind.Label }
	end
	if context.Seat then
		return DescribeSeat(context, entry, context.Seat)
	end

	if entry.Dirty then
		return {
			Label = "Dirty table",
			Action = "Clean",
			Tint = Tints.Bad,
			Fire = function()
				Bus.Cafe.CleanTable:Fire(context.PropId)
			end,
		}
	end
	local customers = context.Session("Customers")
	for _, seat in entry.Seats or {} do
		if seat.CustomerId and customers and customers[seat.CustomerId] then
			return { Label = "Table", Tint = Tints.Guest }
		end
	end
	return { Label = "Free table" }
end

return CafeTable
