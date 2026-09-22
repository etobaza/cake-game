--!strict
-- Actionable cooking routes follow recipe metadata and the kitchen's current contents.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local GardenSource = require(script.Parent.Parent.GardenSource)
local Ingredients = require(script.Parent.Parent.Configs.Registries.Ingredients)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Tables ]]--
local Cooking = {}

--[[ Private Functions ]]--
local function waiting(id: string, title: string, hint: string, target: string?): Types.TutorialGoal
	local goal = State.Goal(id, title, hint, target)
	goal.waiting = true
	return goal
end

local function choose(recipe: any, page: string, mixer: string): Types.TutorialGoal
	local goal = State.Goal(
		"choose_" .. recipe.id,
		"Go to your mixer",
		"Use the mixer to open its recipes. Let's start with " .. recipe.name .. ".",
		mixer
	)
	if page == "RecipeToCook" then
		goal.id = "start_" .. recipe.id
		goal.title = "Start " .. recipe.name
		goal.hint = "Use Start beside this recipe. Its ingredients will appear above your mixer."
		goal.target = { kind = "Recipe", id = recipe.id }
	end
	goal.recipeId = recipe.id
	return goal
end

local function stationGoal(session: any, props: any, id: string, station: any): Types.TutorialGoal?
	if station.State == "Idle" then
		return nil
	end
	if station.State == "Loaded" or (station.State == "Cooking" and (station.HeatPausedAt or 0) > 0) then
		local held = session.Hands[1]
		if held and held.Kind == "Fuel" then
			return State.Goal(
				"fuel_" .. id,
				"Add a log to heat the oven",
				"The dough is inside. A fresh log starts or resumes baking from where it stopped.",
				id
			)
		end
		return State.FreeHands(session, props, "Free your hand so you can carry a log.")
			or State.Goal(
				"wood_" .. id,
				"Take a log from the woodpile",
				"The loaded oven needs firewood. Take one log, then bring it back.",
				"fuel"
			)
	end
	if station.State == "Mixing" or station.State == "Cooking" then
		return waiting(
			"wait_" .. id,
			if station.State == "Mixing" then "Mixing your ingredients…" else "Your dish is cooking…",
			"It will be ready in a moment. The next hint appears when you can collect it.",
			id
		)
	end
	local clear =
		State.FreeHands(session, props, "You carry one item at a time. Free your hand before collecting this batch.")
	if clear then
		return clear
	end
	if station.State == "Burnt" then
		return State.Goal(
			"burnt_" .. id,
			"Take the burnt food out",
			"Empty the oven, throw away the burnt food, then make a fresh batch. Your learned steps are saved.",
			id
		)
	end
	local recipe = Recipes:Get(station.RecipeId)
	local dough = Buildings.Kinds[station.Kind].Mixes and recipe and recipe.cookSeconds > 0
	return State.Goal(
		"collect_" .. id,
		if dough then "Take the dough from the mixer" else "Collect your finished dish",
		"A ready batch stays here until you take it. Baked food can burn if left in the oven.",
		id
	)
end

function Cooking.Garden(cloud: any, session: any, props: any, id: string, source: any): Types.TutorialGoal
	local node = cloud.Garden[source.Group][id]
	local held = session.Hands[1]
	if node and node.Stock > 0 then
		local free = State.FreeHands(
			session,
			props,
			"Harvesting needs an empty hand. Return your tool or put down the item first."
		)
		return free
			or State.Goal(
				"harvest_" .. id,
				"Collect one " .. source.Produce,
				"Each harvest puts one ingredient in your hand. Cared-for sources keep producing.",
				id
			)
	end
	local cared = source.Care == "Hive" or (node and (node.CareRemaining > 0 or node.CleanDay == cloud.Day))
	if cared then
		return waiting(
			"grow_" .. id,
			"Your " .. source.Produce .. " is growing…",
			"Wait until produce is ready, then harvest with an empty hand.",
			id
		)
	end
	if source.Care == "Animal" then
		return State.FreeHands(session, props, "Brushing an animal needs an empty hand.")
			or State.Goal("care_" .. id, "Brush the animal", "Keeping it clean lets it produce ingredients.", id)
	end
	if held and held.Kind == "Tool" and held.Id == Buildings.Kinds.WateringCan.ToolId then
		return State.Goal(
			"water_" .. id,
			"Water the plant",
			"Water keeps it producing. Return the can before harvesting.",
			id
		)
	end
	return State.FreeHands(session, props, "Free your hand to take the watering can.")
		or State.Goal(
			"take_can",
			"Take the watering can",
			"Use the can on the dry plant, then return it to free your hand.",
			Buildings.Kinds.WateringCan.ToolId
		)
end

local function ingredient(cloud: any, session: any, props: any, id: string, mixer: string): Types.TutorialGoal
	local entry = Ingredients:Get(id)
	local name = if entry then entry.name else id
	if Ingredients:IsInfinite(id) then
		local goal = State.Goal(
			"fetch_" .. id,
			"Take one " .. name,
			"Carry it to the mixer. Each trip adds one ingredient; what is already loaded stays in the bowl.",
			`{Buildings.Kinds.Ingredient.Prefix}_{id}`
		)
		goal.itemId = id
		return goal
	end
	if (cloud.Pantry[id] or 0) > 0 then
		local goal = State.Goal(
			"pantry_" .. id,
			"Take " .. name .. " from pantry stock",
			"Stand beside the mixer and press the matching ingredient chip above its bowl.",
			mixer
		)
		goal.target = { kind = "Ingredient", id = id }
		return goal
	end
	for index, delivered in cloud.GardenCart.Queue do
		if delivered ~= id then
			continue
		end
		local outputId = if index == 1 then "rail_output" else `rail_output_{index}`
		return State.Goal(
			"delivery_" .. id,
			"Collect the kitchen delivery",
			"Choose the tray holding the ingredient you need.",
			outputId
		)
	end
	local sourceId, source = GardenSource.Find(id)
	if sourceId and source and (cloud.Base.Upgrades[source.Upgrade] or 0) > 0 then
		return Cooking.Garden(cloud, session, props, sourceId, source)
	end
	return State.Goal(
		"unavailable_" .. id,
		"Choose a recipe with ingredients you have",
		"This recipe needs a garden source you do not own yet. Cancel its idle batch in the recipe list and choose another dish.",
		mixer
	)
end

--[[ Handling ]]--
function Cooking.AtStation(session: any, props: any, id: string, station: any): Types.TutorialGoal?
	return stationGoal(session, props, id, station)
end

function Cooking.Urgent(session: any, props: any): Types.TutorialGoal?
	local bestId: string? = nil
	local best: any = nil
	for id, station in session.Stations do
		if station.State ~= "Ready" or station.BurnAt <= 0 or (station.HeatPausedAt or 0) > 0 then
			continue
		end
		if not best or station.BurnAt < best.BurnAt then
			bestId, best = id, station
		end
	end
	if not best or not bestId then
		return nil
	end
	local goal = stationGoal(session, props, bestId, best)
	if goal then
		goal.urgent = true
		goal.recipeId = best.RecipeId
	end
	return goal
end

function Cooking.Resolve(cloud: any, session: any, props: any, recipe: any, page: string): Types.TutorialGoal?
	local held = session.Hands[1]
	if held and held.Kind == "Burnt" then
		return State.FreeHands(
			session,
			props,
			"Burnt food cannot be served. Make a fresh batch after throwing it away."
		)
	end
	if held and held.Kind == "Dish" and held.Id == recipe.id then
		return nil
	end
	for slot, recipeId in session.Display do
		if recipeId == recipe.id then
			return State.FreeHands(session, props, "Free your hand to collect the dish you already made.")
				or State.Goal(
					"display_take",
					"Take your dish from the display",
					"You already made it. Carry this dish to the guest when their order is ready.",
					Buildings.GetId("Display", slot)
				)
		end
	end
	if held and held.Kind == "Dough" then
		local doughRecipe = Recipes:Get(held.Id)
		local id = doughRecipe and State.Station(session, doughRecipe.station, "Idle")
		if id then
			return State.Goal(
				"load_dough",
				"Put the dough in the " .. string.lower(doughRecipe.station),
				"The station follows this recipe. An oven accepts dough before it has firewood.",
				id
			)
		end
	end
	for id, station in session.Stations do
		if station.State ~= "Idle" then
			return stationGoal(session, props, id, station)
		end
	end
	local startKind = Recipes:GetStartStation(recipe)
	local stationId, station = State.Station(session, startKind)
	if not stationId or not station then
		return waiting(
			"station_missing",
			"Your kitchen is getting ready…",
			"The hint will appear when your bakery is ready.",
			nil
		)
	end
	if startKind ~= "Mixer" then
		return State.FreeHands(session, props, "Free your hand before preparing this drink.")
			or State.Goal(
				"direct_" .. recipe.id,
				"Prepare " .. recipe.name,
				"Use this station to prepare a drink from today's menu.",
				stationId
			)
	end
	if session.Cooking.SelectedRecipeId ~= recipe.id then
		local selected = Recipes:Get(session.Cooking.SelectedRecipeId)
		for _ in station.Loaded do
			if selected then
				return Cooking.Resolve(cloud, session, props, selected, page)
			end
		end
		if held and session.Cooking.SelectedRecipeId then
			return State.FreeHands(
				session,
				props,
				"Free your hand before changing the recipe to match the guest's order."
			)
		end
		return choose(recipe, page, stationId)
	end
	for id, amount in recipe.ingredients do
		if (station.Loaded[id] or 0) >= amount or Ingredients:IsInfinite(id) or (cloud.Pantry[id] or 0) > 0 then
			continue
		end
		local available = held and held.Kind == "Ingredient" and held.Id == id
		for _, delivered in cloud.GardenCart.Queue do
			if delivered == id then
				available = true
			end
		end
		local _, source = GardenSource.Find(id)
		available = available or (source and (cloud.Base.Upgrades[source.Upgrade] or 0) > 0)
		if available then
			continue
		end
		local goal = State.Goal(
			"unavailable_" .. id,
			"Choose a recipe you can make",
			"This recipe needs a garden source you do not own. Open the recipes and cancel this batch; loaded garden produce returns to the pantry.",
			stationId
		)
		goal.recovery = true
		if page == "RecipeToCook" then
			goal.title = "Cancel this unfinished recipe"
			goal.target = { kind = "Recipe", id = recipe.id, control = "InProgress" }
		end
		return goal
	end
	if page == "RecipeToCook" then
		return State.Gui(
			"close_recipes",
			"Return to your mixer",
			"Your recipe is selected. Its ingredients are now shown above the bowl.",
			"RecipeToCook.MainFrame.Header.Exit"
		)
	end
	local missing = {}
	for id, amount in recipe.ingredients do
		if (station.Loaded[id] or 0) < amount then
			missing[#missing + 1] = id
		end
	end
	table.sort(missing)
	if
		held
		and held.Kind == "Ingredient"
		and recipe.ingredients[held.Id]
		and (station.Loaded[held.Id] or 0) < recipe.ingredients[held.Id]
	then
		return State.Goal(
			"load_" .. held.Id,
			"Add it to the mixer",
			"You have the ingredient in your hand. Use the mixer to add it to this batch.",
			stationId
		)
	end
	local free =
		State.FreeHands(session, props, "This item is not needed in the bowl right now. Free your hand to continue.")
	if free then
		return free
	end
	if missing[1] then
		return ingredient(cloud, session, props, missing[1], stationId)
	end
	return State.Goal(
		"mix",
		"Start mixing",
		"Every ingredient is in the bowl. Use Mix once; your character stays here until the batch is ready.",
		stationId
	)
end

return Cooking
