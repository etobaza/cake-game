--!strict
-- The garden accepts one carried ingredient; each kitchen tray offers its own delivery.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local CarryPolicy = require(_Shared.CarryPolicy)
local Config = require(_Shared.Configs.Garden)
local Ingredients = require(_Shared.Configs.Registries.Ingredients)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local RailCart = {}

--[[ Handling ]]--
function RailCart.Describe(context: Types.Context): Types.PromptState
	local cart = context.Cloud({ "GardenCart" })
	if not cart then
		return { Label = "Rail cart" }
	end
	local day = context.Session("Day")
	if not day or day.Phase == "Summary" then
		return { Label = "Rail cart", Action = "Paused" }
	end
	local held = context.Held()
	if context.Kind == "RailOutput" then
		local index = math.max(1, context.Index)
		local id = cart.Queue[index]
		if not id then
			return { Label = "Deliveries" }
		end
		local wagon = cart.Carts and cart.Carts[index]
		if not wagon or not wagon.Arrived then
			return { Label = "Rail cart", Action = "Arriving" }
		end
		local blocked = held ~= nil and not CarryPolicy.CanReplace(held)
		return {
			Label = `{context.ItemName({ Kind = "Ingredient", Id = id })} · {#cart.Queue}/{Config.CartCapacity}`,
			Action = if blocked then "Hands full" else "Take",
			Fire = if blocked
				then nil
				else function(): ()
					Bus.Garden.CartTake:Fire(context.PropId, id, wagon.Id)
				end,
		}
	end
	if #cart.Queue >= Config.CartCapacity then
		return { Label = "Rail cart", Action = "Collect deliveries" }
	end
	if cart.SpawnRemaining > 0 then
		return { Label = "Rail cart", Action = "Next cart arriving" }
	end
	local accepted = held and held.Kind == "Ingredient" and Ingredients:Get(held.Id)
	return {
		Label = `Rail cart {#cart.Queue}/{Config.CartCapacity}`,
		Action = if accepted then "Send" else "Bring an ingredient",
		Fire = if accepted
			then function(): ()
				Bus.Garden.CartLoad:Fire(context.PropId)
			end
			else nil,
	}
end

return RailCart
