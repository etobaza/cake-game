-- Prompt view of a shared cafe table. A matching held dish selects its waiting guest;
-- cleaning clears dirty places while another guest may still be ordering or eating.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local BuildingsConfig = require(_Shared.Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataList = require(_Shared.DataList)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local Tints = require(script.Parent.Tints)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local CafeTable = {}

--[[ Handling ]]--
function CafeTable.Describe(context: Types.Context): Types.PromptState
	local kind = BuildingsConfig.Kinds[context.Kind]
	local tables = context.Session(kind.StateField :: string)
	local entry = tables and tables[context.PropId]
	if not entry then
		return { Label = kind.Label }
	end

	local customers = context.Session("Customers")
	local held = context.Held()
	local rawRecipe = if held and held.Kind == "Dough" then Recipes:Get(held.Id) else nil
	-- Keep the serve action reachable so an unfinished oven dish can explain its missing step.
	local canAttemptServe = held and (held.Kind == "Dish" or (rawRecipe and rawRecipe.station == "Oven"))
	local labels = {}
	local serveId: string? = nil
	local takeOrderId: string? = nil
	local serveLabel = ""
	local takeOrderLabel = ""
	for index, seat in entry.Seats or {} do
		local customerId = seat.CustomerId
		local customer = customerId and customers and customers[customerId]
		if not customer then
			continue
		end
		if customer.State == "Arriving" then
			labels[#labels + 1] = `{index}: Arriving`
			continue
		end
		if customer.State == "Choosing" then
			labels[#labels + 1] = `{index}: Choosing`
			if not takeOrderId then
				takeOrderLabel = `Seat {index}`
			end
			takeOrderId = takeOrderId or customerId
			continue
		end
		if customer.State == "Eating" then
			labels[#labels + 1] = `{index}: Eating`
			continue
		end
		-- Orders and patience already have their own HUD cards; the prompt identifies the seat.
		labels[#labels + 1] = `{index}: Waiting`
		if
			not serveId
			and customer.State == "Waiting"
			and held
			and canAttemptServe
			and DataList.Contains(customer.Orders, held.Id)
		then
			serveId = customerId
			serveLabel = `Seat {index}`
		end
	end

	local label = table.concat(labels, " / ")
	if serveId then
		local customerId = serveId
		return {
			Label = serveLabel,
			Action = "Serve",
			Tint = Tints.Guest,
			Fire = function()
				Bus.Cafe.Serve:Fire(customerId)
			end,
		}
	end
	if takeOrderId then
		local customerId = takeOrderId
		return {
			Label = takeOrderLabel,
			Action = "Take order",
			Tint = Tints.Guest,
			Fire = function()
				Bus.Cafe.TakeOrder:Fire(customerId)
			end,
		}
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
	return if label == "" then { Label = "Free table" } else { Label = label, Tint = Tints.Guest }
end

return CafeTable
