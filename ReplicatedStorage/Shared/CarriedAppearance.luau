--!strict
-- One interpretation of the server's appearance attribute for props and animation layers.

--[[ Services ]]--
local HttpService = game:GetService("HttpService")

--[[ Types ]]--
export type Item = { Kind: string, Id: string?, PickupOrigin: { number }?, PickupAt: number? }

--[[ Constants ]]--
local HOLD_KINDS: { [string]: string } = {
	Dish = "Trayfoodhold",
	Dough = "Trayfoodhold",
	Burnt = "Trayfoodhold",
	Ingredient = "Trayfoodhold",
	Fuel = "Carry",
}

--[[ Tables ]]--
local CarriedAppearance = {}

--[[ Private Functions ]]--
local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

--[[ Handling ]]--
function CarriedAppearance.Decode(value: any): Item?
	if typeof(value) ~= "string" then
		return nil
	end
	if value == "" then
		return { Kind = "Empty" }
	end
	local ok, item = pcall(function(): any
		return HttpService:JSONDecode(value)
	end)
	if not ok then
		warn("[CarriedAppearance] Invalid carried-food appearance")
		return nil
	end
	if typeof(item) ~= "table" or typeof(item.Kind) ~= "string" or typeof(item.Id) ~= "string" then
		return nil
	end
	local origin = item.PickupOrigin
	if
		typeof(origin) ~= "table"
		or not finite(item.PickupAt)
		or not finite(origin[1])
		or not finite(origin[2])
		or not finite(origin[3])
	then
		item.PickupOrigin, item.PickupAt = nil, nil
	end
	return item
end

function CarriedAppearance.HasTray(item: Item?): boolean
	return item ~= nil and HOLD_KINDS[item.Kind] == "Trayfoodhold"
end

function CarriedAppearance.HasCarriedModel(item: Item?): boolean
	return item ~= nil and HOLD_KINDS[item.Kind] ~= nil
end

function CarriedAppearance.GetHold(item: Item?): string?
	if not item then
		return nil
	end
	if item.Kind == "Tool" and item.Id == "broom" then
		return "Broomhold"
	end
	if item.Kind == "Tool" and item.Id == "watering_can" then
		return "LeikaHold"
	end
	return HOLD_KINDS[item.Kind]
end

return CarriedAppearance
