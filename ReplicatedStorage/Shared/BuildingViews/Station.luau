--!strict
-- Prompt view of a kitchen station: what it is doing now and what the player can do with it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local CarryPolicy = require(_Shared.CarryPolicy)
local IngredientCard = require(_Shared.UI.IngredientCard)
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

-- What the bowl still lacks, in the floating card's order.
local function MissingNames(recipe: Recipes.RecipeEntry, station: any): { string }
	local names = {}
	for _, entry in IngredientCard.Sorted(recipe) do
		local loaded = (station.Loaded and station.Loaded[entry.Id]) or 0
		if loaded < entry.Amount then
			names[#names + 1] = string.lower(IngredientCard.Name(entry.Id))
		end
	end

	return names
end

local function GetKind(context: Types.Context): BuildingsConfig.Kind
	return BuildingsConfig.Kinds[context.Kind]
end

-- Dough this station bakes: pressing a finished station swaps it for the result.
local function CanSwap(context: Types.Context, held: any): boolean
	if GetKind(context).Mixes or not held or held.Kind ~= "Dough" then
		return false
	end
	local recipe = Recipes:Get(held.Id)
	return recipe ~= nil and recipe.station == context.Kind
end

-- Whether a dish on today's menu that starts at this station asks for the ingredient: the recipe
-- list offers only those, so without one it has nothing to pick for what the player carries.
local function MenuUses(context: Types.Context, ingredientId: string): boolean
	local day = context.Session("Day")
	for _, recipeId in (day and day.Menu or {}) do
		local recipe = Recipes:Get(recipeId)
		if recipe and Recipes:GetStartStation(recipe) == context.Kind and recipe.ingredients[ingredientId] then
			return true
		end
	end

	return false
end

-- Garden produce the mixer cannot use goes into the pantry instead of the trash. Staples cannot.
local function DescribeStore(held: any, fireLoad: () -> ()): Types.PromptState?
	local ingredient = Ingredients:Get(held.Id)
	if not ingredient or Ingredients:IsInfinite(held.Id) then
		return nil
	end

	return { Label = `{ingredient.name} to pantry`, Action = "Store", Fire = fireLoad }
end

-- An ingredient in hand: added while the batch needs it, garden produce it cannot use goes into the
-- pantry, and a staple it cannot use goes back to its own tray (that tray's prompt, not this one).
local function DescribeIngredient(
	recipe: Recipes.RecipeEntry,
	station: any,
	held: any,
	fireLoad: () -> ()
): Types.PromptState
	local ingredient = Ingredients:Get(held.Id)
	local ingredientName = if ingredient then ingredient.name else held.Id
	local needed = recipe.ingredients[held.Id]
	local loaded = (station.Loaded and station.Loaded[held.Id]) or 0
	if needed and loaded < needed then
		return { Label = ingredientName, Action = "Add", Fire = fireLoad }
	end

	local store = DescribeStore(held, fireLoad)
	if store then
		return store
	end

	return {
		Label = if needed then "Already added" else "Wrong ingredient",
		Tint = Tints.Bad,
		Status = true,
		LineOnly = true,
	}
end

-- A finished batch: Take, or Swap for held dough. Any other full hand reads as a status instead of a
-- press the server would refuse.
local function DescribeFinished(context: Types.Context, station: any, fireCollect: () -> ()): Types.PromptState
	local burnt = station.State == "Burnt"
	local name = context.RecipeName(station.RecipeId)
	local label = if burnt
		then "Burnt"
		elseif (station.HeatPausedAt or 0) > 0 then `{name} · Fire out`
		elseif station.BurnAt > 0 then `Burns in {context.Seconds(station.BurnAt)}s`
		else name
	local tint = if burnt then Tints.Bad else Tints.Ready
	local held = context.Held()
	local swap = CanSwap(context, held)
	if held and not swap and not CarryPolicy.CanReplace(held) then
		return { Label = `{label} · Hands full`, Tint = tint, Status = true, LineOnly = true }
	end

	return {
		Label = label,
		Action = if swap then "Swap" else "Take",
		Fire = fireCollect,
		Tint = tint,
	}
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
		local chosen = selected ~= nil and Recipes:GetStartStation(selected) == context.Kind
		-- Produce no dish on today's menu uses (an empty menu included) would find nothing in the list.
		if not chosen and held and held.Kind == "Ingredient" and not MenuUses(context, held.Id) then
			local store = DescribeStore(held, FireLoad)
			if store then
				return store
			end
		end

		-- Cooking is gated on today's menu: an empty list would open to nothing.
		if MenuIsEmpty(context) then
			return { Label = "Choose menu" }
		end

		-- The prompt opens the list only while no dish is chosen. Once one is, the staple trays beside
		-- the bowl keep the key; the floating card above the bowl changes the dish (MixHandler).
		if not selected or not chosen then
			return {
				Label = kind.Label,
				Action = "Recipes",
				Fire = OpenRecipes,
			}
		end

		if held and held.Kind == "Ingredient" then
			return DescribeIngredient(selected, station, held, FireLoad)
		end

		local missing = MissingNames(selected, station)
		if #missing == 0 then
			return {
				Label = selected.name,
				Action = "Mix",
				Fire = function()
					Bus.Kitchen.Mix:Fire(context.PropId)
				end,
			}
		end

		return { Label = `Needs {table.concat(missing, ", ")}`, Status = true, LineOnly = true }
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
		return { Label = "Needs firewood", Status = true, Alert = true }
	end

	if state == "Mixing" then
		return {
			Label = `Mixing {context.Seconds(station.ReadyAt)}s`,
			Tint = Tints.Busy,
			Status = true,
		}
	end

	if state == "Cooking" then
		if (station.HeatPausedAt or 0) > 0 then
			return { Label = "Baking paused · Needs firewood", Tint = Tints.Busy, Status = true, Alert = true }
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
			Status = true,
		}
	end

	if state == "Burnt" or state == "Ready" then
		return DescribeFinished(context, station, FireCollect)
	end

	return DescribeIdle(context, station)
end

return Station
