--!strict
-- Prompt view of one display slot: the dish on it, or an offer to put one down.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local Tints = require(script.Parent.Tints)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local DisplaySlot = {}

--[[ Handling ]]--
function DisplaySlot.Describe(context: Types.Context): Types.PromptState
	local display = context.Session(BuildingsConfig.Kinds[context.Kind].StateField :: string) or {}
	local index = context.Index

	local function FireTake(): ()
		Bus.Cafe.DisplayTake:Fire(index)
	end

	local function FirePlace(): ()
		Bus.Cafe.DisplayPlace:Fire(index)
	end

	-- The slot key may arrive as a number or a string — replication makes no promise about the type.
	local dish = display[index] or display[tostring(index)]
	local held = context.Held()
	local leftovers = context.Session("DisplayLeftovers") or {}
	local label = if leftovers[index] or leftovers[tostring(index)] then "Leftover Pastry" else context.RecipeName(dish)

	if dish then
		if held and (held.Kind == "Dish" or held.Kind == "Leftover") then
			return {
				Label = label,
				Action = `Switch with {context.ItemName(held)}`,
				Fire = FirePlace,
				Tint = Tints.Ready,
			}
		end
		return {
			Label = label,
			Action = "Take",
			Fire = FireTake,
			Tint = Tints.Ready,
		}
	end

	if not held or (held.Kind ~= "Dish" and held.Kind ~= "Leftover") then
		return { Label = `Slot {index}` }
	end

	return {
		Label = `Slot {index}`,
		Action = "Place",
		Fire = FirePlace,
	}
end

return DisplaySlot
