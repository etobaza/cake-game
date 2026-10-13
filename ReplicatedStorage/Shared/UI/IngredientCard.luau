--!strict
-- The mixer ingredient card shared by the station pick screen (RecipePickHandler) and the floating
-- mixer billboard (MixHandler): a recipe's ingredients in a fixed order, the reusable Done/NotDone
-- chip pairs, and the press that loads a pantry ingredient. Shared code never requires a handler, so
-- callers pass client data in.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local Animate = require(script.Parent.Animate)
local Bus = require(_Shared.Bus)
local GardenSource = require(_Shared.GardenSource)
local IngredientChip = require(script.Parent.IngredientChip)
local Ingredients = require(_Configs.Registries.Ingredients)
local Press = require(script.Parent.Press)
local Recipes = require(_Configs.Registries.Recipes)

--[[ Types ]]--
export type ChipPair = { Done: Frame, NotDone: Frame }
export type Entry = { Id: string, Amount: number }
export type Unit = { Id: string, Required: number }
export type ChipOptions = {
	-- The station a pressed chip loads its ingredient into.
	StationId: string,
	-- Units of the ingredient in the player's pantry.
	PantryCount: (ingredientId: string) -> number,
	-- A world-space card is not scrollable and must leave mouse right-drag and the wheel to the
	-- camera, so it presses on contact. A screen card sits in a scrolling frame and commits only on
	-- a tap, so a scroll drag that starts on a chip never loads anything.
	Floating: boolean,
}

--[[ Tables ]]--
local IngredientCard = {}

--[[ Private Functions ]]--
local function takeFromPantry(chip: Frame, options: ChipOptions): ()
	local ingredientId = chip:GetAttribute("IngredientId")
	if typeof(ingredientId) ~= "string" or Ingredients:IsInfinite(ingredientId) then
		return
	end
	if options.PantryCount(ingredientId) <= 0 then
		return
	end
	Bus.Kitchen.TakePantry:Fire(options.StationId, ingredientId)
end

--[[ Handling ]]--
function IngredientCard.Name(ingredientId: string): string
	local ingredient = Ingredients:Get(ingredientId)

	return if ingredient then ingredient.name else ingredientId
end

-- Ingredients of a recipe in a fixed order: the table is a dictionary, and a card that reshuffles
-- its chips on every refresh reads as broken.
function IngredientCard.Sorted(recipe: Recipes.RecipeEntry): { Entry }
	local sorted: { Entry } = {}

	for ingredientId, amount in recipe.ingredients do
		sorted[#sorted + 1] = { Id = ingredientId, Amount = amount }
	end

	table.sort(sorted, function(left: Entry, right: Entry): boolean
		return IngredientCard.Name(left.Id) < IngredientCard.Name(right.Id)
	end)

	return sorted
end

-- One entry per required unit, in the sorted order: flour x4 becomes four separate flour chips.
function IngredientCard.Units(recipe: Recipes.RecipeEntry): { Unit }
	local units: { Unit } = {}

	for _, entry in IngredientCard.Sorted(recipe) do
		for required = 1, entry.Amount do
			units[#units + 1] = { Id = entry.Id, Required = required }
		end
	end

	return units
end

-- The most distinct ingredients any recipe asks for: a card with one chip per ingredient keeps that many.
function IngredientCard.MostIngredients(): number
	local most = 0

	for _, recipe in Recipes:Values() do
		local count = 0
		for _ in recipe.ingredients do
			count += 1
		end
		most = math.max(most, count)
	end

	return most
end

-- The most units any recipe asks for: a card with one chip per unit keeps that many.
function IngredientCard.MostUnits(): number
	local most = 0

	for _, recipe in Recipes:Values() do
		local count = 0
		for _, amount in recipe.ingredients do
			count += amount
		end
		most = math.max(most, count)
	end

	return most
end

-- What the station of `stationKind` holds, by ingredient, from the session Stations list.
function IngredientCard.Loaded(stations: any, stationKind: string): { [string]: number }
	for _, station in stations or {} do
		if station.Kind == stationKind then
			return station.Loaded or {}
		end
	end

	return {}
end

-- Detached, prepared copies of the authored Done/NotDone chip pair inside `holder`, or nil when
-- the art is incomplete. The caller owns and destroys the returned templates.
function IngredientCard.Templates(holder: Instance): (Frame?, Frame?)
	local done = holder:FindFirstChild("Done")
	local notDone = holder:FindFirstChild("NotDone")
	local chipIcon = done and done:FindFirstChild("Icon")
	if
		not done
		or not done:IsA("Frame")
		or not notDone
		or not notDone:IsA("Frame")
		or not chipIcon
		or not chipIcon:IsA("ImageLabel")
	then
		return nil, nil
	end

	local doneTemplate = done:Clone()
	local notDoneTemplate = notDone:Clone()
	IngredientChip.Prepare(notDoneTemplate, chipIcon)
	IngredientChip.Prepare(doneTemplate, chipIcon)

	return doneTemplate, notDoneTemplate
end

-- Clears the authored chips from `holder` and fills it with `count` hidden Done/NotDone pairs. Both
-- are kept per place and toggled; pressing an unlit chip loads that ingredient from the pantry.
-- The janitor owns the chips and their bindings.
function IngredientCard.BuildChips(
	holder: Instance,
	doneTemplate: Frame,
	notDoneTemplate: Frame,
	count: number,
	janitor: any,
	options: ChipOptions
): { ChipPair }
	for _, chip in holder:GetChildren() do
		if chip:IsA("Frame") then
			chip:Destroy()
		end
	end

	local chips: { ChipPair } = {}
	for index = 1, count do
		local done = doneTemplate:Clone()
		done.Name = `Done{index}`
		done.LayoutOrder = index
		done.Visible = false
		done.Parent = holder
		janitor:Add(done, "Destroy")
		janitor:Add(Animate.Scale(done), "destroy")

		local notDone = notDoneTemplate:Clone()
		notDone.Name = `NotDone{index}`
		notDone.LayoutOrder = index
		notDone.Visible = false
		notDone.Parent = holder
		janitor:Add(notDone, "Destroy")
		local function take(): ()
			takeFromPantry(notDone, options)
		end
		if options.Floating then
			janitor:Add(Press.Bind(notDone, take), "Destroy")
			-- Right-drag and the wheel over the floating card still turn and zoom the camera on PC.
			janitor:Add(Press.SinkUnlessMouse(notDone), "Destroy")
		else
			janitor:Add(Press.BindTap(notDone, take), "Destroy")
		end

		chips[index] = { Done = done, NotDone = notDone }
	end

	return chips
end

function IngredientCard.ShowChip(chip: ChipPair, ingredientId: string, caption: string, complete: boolean): ()
	IngredientChip.Show(chip.Done, ingredientId, caption)
	IngredientChip.Show(chip.NotDone, ingredientId, caption)

	-- Lit chips spring in only as they light up, not on every refresh.
	if complete and not chip.Done.Visible then
		Animate.Pop(chip.Done)
	end

	chip.Done.Visible = complete
	chip.NotDone.Visible = not complete
end

function IngredientCard.HideChip(chip: ChipPair): ()
	chip.Done.Visible = false
	chip.NotDone.Visible = false
	-- An unused place must not keep loading the ingredient it showed last.
	chip.NotDone:SetAttribute("IngredientId", nil)
end

-- One line of the source hint: where the player gets a missing ingredient.
function IngredientCard.SourceHint(ingredientId: string, cloud: any): string
	return `{IngredientCard.Name(ingredientId)}: {GardenSource.Describe(ingredientId, cloud)}`
end

function IngredientCard.ShowHints(label: Instance?, hints: { string }): ()
	if label and label:IsA("TextLabel") then
		label.Text = table.concat(hints, "\n")
		label.Visible = #hints > 0
	end
end

return IngredientCard
