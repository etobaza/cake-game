-- Prompt view of a kitchen station: what it is doing now and what the player can do with it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local Ingredients = require(_Configs.Registries.Ingredients)
-- Views run on the client only (InteractHandler is their one consumer), so the page store is safe here.
local Pages = require(_Shared.UI.Stores.Pages)
local Recipes = require(_Configs.Registries.Recipes)
local Tints = require(script.Parent.Tints)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local Station = {}

--[[ Private Functions ]]--
-- Counted rather than measured with `#`: the day table is a replicated mirror, and its array length
-- is not something to trust from the outside.
local function MenuIsEmpty(context: Types.Context): boolean
	local day = context.Session("Day")

	for _ in (day and day.Menu or {}) do
		return false
	end

	return true
end

local function SelectedRecipe(context: Types.Context): Recipes.RecipeEntry?
	local cooking = context.Session("Cooking")
	return cooking and cooking.SelectedRecipeId and Recipes:Get(cooking.SelectedRecipeId)
end

local function hasMissingIngredients(recipe: Recipes.RecipeEntry, station: any): boolean
	for ingredientId, amount in recipe.ingredients do
		local loaded = (station.Loaded and station.Loaded[ingredientId]) or 0
		if loaded < amount then
			return true
		end
	end

	return false
end

local function GetKind(context: Types.Context): BuildingsConfig.Kind
	return BuildingsConfig.Kinds[context.Kind]
end

local function FuelNote(context: Types.Context, station: any): string
	if not GetKind(context).UsesFuel then
		return ""
	end
	return if station.Fuel > 0 then ` · Fire {context.Seconds(station.FuelEndsAt)}s` else " · No fire"
end

local function DescribeIdle(context: Types.Context, station: any): Types.PromptState
	local function FireLoad(): ()
		Bus.Kitchen.Load:Fire(context.PropId)
	end

	-- The recipe list is where a dish is chosen, changed or cancelled: it is the mixer's own page.
	local function OpenRecipes(): ()
		Pages.Open(Pages.Names.RecipeToCook)
	end

	local fuelNote = FuelNote(context, station)
	local idleLabel = `{GetKind(context).Label}{fuelNote}`
	local held = context.Held()
	local selected = SelectedRecipe(context)
	local kind = GetKind(context)

	local dough = if held and held.Kind == "Dough" then Recipes:Get(held.Id) else nil
	if dough and dough.station == context.Kind then
		return {
			Label = dough.name,
			Action = "Load",
			Fire = FireLoad,
		}
	end

	if kind.Mixes then
		-- Cooking is gated on today's menu: an empty list would open to nothing.
		if MenuIsEmpty(context) then
			return { Label = "Choose menu" }
		end

		if not selected or Recipes:GetStartStation(selected) ~= context.Kind then
			return {
				Label = kind.Label,
				Action = "Recipes",
				Fire = OpenRecipes,
			}
		end

		-- An ingredient in hand always attempts loading, even when the bowl is complete.
		-- Keep rejected attempts actionable so the server can send the matching status toast.
		if held and held.Kind == "Ingredient" then
			local ingredient = Ingredients:Get(held.Id)
			local ingredientName = if ingredient then ingredient.name else held.Id
			local needed = selected.ingredients[held.Id]
			local loaded = (station.Loaded and station.Loaded[held.Id]) or 0
			if needed and loaded < needed then
				return {
					Label = ingredientName,
					Action = "Add",
					Fire = FireLoad,
				}
			end

			return {
				Label = if needed then "Already added" else "Wrong ingredient",
				Action = "Add",
				Fire = FireLoad,
				Tint = Tints.Bad,
			}
		end

		if not hasMissingIngredients(selected, station) then
			return {
				Label = selected.name,
				Action = "Mix",
				Fire = function()
					Bus.Kitchen.Mix:Fire(context.PropId)
				end,
			}
		end

		-- Nothing useful in the hands: the list is where the dish is swapped or the batch cancelled.
		return {
			Label = selected.name,
			Action = "Recipes",
			Fire = OpenRecipes,
		}
	end

	local day = context.Session("Day")
	local directRecipe = Recipes:GetDirectRecipe(day and day.Menu or {}, context.Kind, selected and selected.id)
	if directRecipe then
		return {
			Label = directRecipe.name,
			Action = "Prepare",
			Fire = function()
				Bus.Kitchen.Mix:Fire(context.PropId)
			end,
		}
	end

	-- Let the server explain the missing batch instead of making an installed station look broken.
	if kind.LoadFeedback then
		return { Label = idleLabel, Action = "Load", Fire = FireLoad }
	end

	-- Cooking is gated on today's menu, and a station with no action on it reads as broken. Say which
	-- of the two it is instead of standing there silent.
	if MenuIsEmpty(context) then
		return { Label = "Choose menu" }
	end

	return { Label = idleLabel }
end

--[[ Handling ]]--
function Station.Describe(context: Types.Context): Types.PromptState
	local function FireCollect(): ()
		Bus.Kitchen.Collect:Fire(context.PropId)
	end

	local stations = context.Session(GetKind(context).StateField :: string)
	local station = stations and stations[context.PropId]
	if not station then
		return { Label = "Not installed" }
	end

	local state = station.State
	local held = context.Held()
	-- A log can refresh the fire in every oven phase, including paused or finished food.
	if GetKind(context).UsesFuel and held and held.Kind == "Fuel" then
		return {
			Label = `{GetKind(context).Label}{FuelNote(context, station)}`,
			Action = "Add firewood",
			Fire = function()
				Bus.Kitchen.Refuel:Fire(context.PropId)
			end,
		}
	end
	if state == "Loaded" then
		return { Label = "Needs firewood" }
	end

	if state == "Mixing" then
		return {
			Label = `Mixing {context.Seconds(station.ReadyAt)}s`,
			Tint = Tints.Busy,
		}
	end

	if state == "Cooking" then
		if (station.HeatPausedAt or 0) > 0 then
			return { Label = "Baking paused · Needs firewood", Tint = Tints.Busy }
		end
		local verb = if context.Kind == "Oven"
			then "Baking"
			elseif context.Kind == "Freezer" then "Freezing"
			else "Preparing"
		return {
			Label = `{verb} {context.Seconds(station.ReadyAt)}s`,
			Action = if GetKind(context).LoadFeedback then "Check" else nil,
			Fire = if GetKind(context).LoadFeedback then FireCollect else nil,
			Tint = Tints.Busy,
		}
	end

	if state == "Burnt" then
		return {
			Label = "Burnt",
			Action = "Take",
			Fire = FireCollect,
			Tint = Tints.Bad,
		}
	end

	if state == "Ready" then
		local name = context.RecipeName(station.RecipeId)
		local label = if (station.HeatPausedAt or 0) > 0
			then `{name} · Fire out`
			elseif station.BurnAt > 0 then `Burns in {context.Seconds(station.BurnAt)}s`
			else name

		return {
			Label = label,
			Action = "Take",
			Fire = FireCollect,
			Tint = Tints.Ready,
		}
	end

	return DescribeIdle(context, station)
end

return Station
