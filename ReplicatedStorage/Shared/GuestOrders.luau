--!strict
-- Reads a seated guest's order state from the replicated customer record. The server owns the
-- record (CustomerHandler/GuestState); the order cards, speech bubbles and table prompts all derive
-- the same answers here so they never disagree about what a guest needs.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Config = require(ReplicatedStorage.Shared.Configs.Orders)
local DataList = require(ReplicatedStorage.Shared.DataList)
local Recipes = require(ReplicatedStorage.Shared.Configs.Registries.Recipes)
local Tables = require(ReplicatedStorage.Shared.Configs.TableMenus)

--[[ Types ]]--
-- What the guest needs next, as the order card colours it (Config.CardStatus.Colors).
export type Need = "Choosing" | "Ready" | "Cook" | "Serve" | "Eating"

--[[ Tables ]]--
local GuestOrders = {}

--[[ Handling ]]--
-- Number dining places in purchase order: the starting table owns 1/2, the upgrade 3/4.
-- These identify seats, so serving an earlier order never renumbers the remaining cards.
function GuestOrders.SeatLabel(tableId: string, seatIndex: number?): string
	local slotOrder = Buildings.Kinds.Table.SlotOrder
	local tableIndex = Buildings.GetIndex(tableId)
	local tableNumber = if slotOrder then table.find(slotOrder, tableIndex) or tableIndex else tableIndex
	return `#{(tableNumber - 1) * Tables.SeatCount + (seatIndex or 1)}`
end

-- Finished choosing and waiting for the player's Take order.
function GuestOrders.IsReady(customer: any, now: number): boolean
	local endsAt = customer.ChoosingEndsAt or 0
	return customer.State == "Choosing" and endsAt > 0 and now >= endsAt
end

-- Share of patience left, 0-1. A guest still reading the menu, a protected tutorial guest and an
-- eating guest have no running clock, so they read as full.
function GuestOrders.Remaining(customer: any, now: number): number
	local endsAt = customer.PatienceEndsAt or 0
	if customer.TutorialProtected or endsAt <= 0 or customer.State == "Eating" then
		return 1
	end
	return math.clamp((endsAt - now) / math.max(customer.Patience or 1, 1), 0, 1)
end

-- Ordered dish names joined for display; empty until the order is placed.
function GuestOrders.DishNames(customer: any): string
	local names: { string } = {}
	for _, recipeId in customer.Orders or {} do
		local recipe = Recipes:Get(recipeId)
		if recipe then
			names[#names + 1] = recipe.name
		end
	end
	return table.concat(names, " + ")
end

-- What the guest needs next, and the line the order card shows for it. `held` is the item in the
-- local player's hands (nil when empty).
function GuestOrders.Need(customer: any, held: any?, now: number): (Need, string)
	if customer.State == "Eating" then
		return "Eating", "Eating"
	end
	if customer.State == "Choosing" then
		if GuestOrders.IsReady(customer, now) then
			return "Ready", "Take order!"
		end
		return "Choosing", "Choosing"
	end
	local names = GuestOrders.DishNames(customer)
	if held and held.Kind == "Dish" and DataList.Contains(customer.Orders, held.Id) then
		return "Serve", `Serve {names}`
	end
	return "Cook", names
end

-- Unserved orders per recipe across every guest who has ordered: the recipe pick shows these.
function GuestOrders.CountWaiting(customers: any): { [string]: number }
	local counts: { [string]: number } = {}
	for _, customer in customers or {} do
		if customer.State ~= "Waiting" or not customer.TableId then
			continue
		end
		for _, recipeId in customer.Orders or {} do
			counts[recipeId] = (counts[recipeId] or 0) + 1
		end
	end
	return counts
end

-- Seconds the player has left to take a ready guest's order before they order on their own.
function GuestOrders.FallbackAt(customer: any): number
	local endsAt = customer.ChoosingEndsAt or 0
	return if endsAt > 0 then endsAt + Config.TakeOrderFallbackSeconds else 0
end

return GuestOrders
