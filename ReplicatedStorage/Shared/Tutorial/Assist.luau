--!strict
-- What a helper would suggest right now, after the introduction. Each situation names its cause in
-- a few words; the step is the concrete action. Pure reads: timing and display live in Coach.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local Config = require(script.Parent.Parent.Configs.Tutorial)
local DayCycle = require(script.Parent.Parent.Configs.DayCycle)
local Cooking = require(script.Parent.Cooking)
local Policy = require(script.Parent.Parent.TutorialPolicy)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Constants ]]--
local OPEN_CLOCK = "UI.HUD.Time"
local MENU_BUTTON = "BakeryMenu.MainFrame.Header.Buttons.Menu"
local NEXT_DAY_BUTTON = "BakeryMenu.MainFrame.Header.Buttons.NextDay"
local MENU_GRID = "Inventory.MainFrame.Container.Content"
local WINDOW = "window_1"
-- Guest states whose order is still to be served.
local UNSERVED = { Queued = true, Arriving = true, Choosing = true, Waiting = true }

--[[ Tables ]]--
local Assist = {}
-- The cause behind a cooking step, keyed by the step id's first word. Missing words fall back to
-- the guest's order, which already explains why the step matters.
local Causes: { [string]: string } = {
	wood = "The oven needs firewood to bake",
	fuel = "Add the log to heat the oven",
	collect = "Your batch is ready to collect",
	burnt = "Burnt food is blocking the oven",
	choose = "Pick a recipe at the mixer first",
	start = "Start the recipe you picked",
	close = "Close the recipes to keep cooking",
	fetch = "The mixer still needs ingredients",
	pantry = "The mixer still needs ingredients",
	delivery = "The mixer still needs ingredients",
	harvest = "The mixer still needs ingredients",
	load = "Add what you carry to the mixer",
	mix = "Everything is in: start mixing",
	unavailable = "This recipe needs an ingredient you lack",
	store = "Free your hands to keep working",
	discard = "Burnt food can't be served",
	water = "Thirsty plants stop growing",
	take_can = "Thirsty plants stop growing",
	care = "Dirty animals stop producing",
	display = "Your dish is waiting on the display",
	direct = "Make it at its own station",
	["return"] = "Put the tool back to free your hands",
}

--[[ Private Functions ]]--
local function word(id: string): string
	return string.match(id, "^%a+") or id
end

type Delay = "Stuck" | "Urgent" | "Prep" | "Feature" | "Summary" | "Idle" | "Waste"

local function stuck(key: string, message: string, step: Types.TutorialGoal?, delay: Delay?): Types.CoachSituation?
	if not step or step.waiting then
		return nil
	end
	return { key = `{key}:{step.id}`, message = message, step = step, delay = delay or "Stuck" }
end

-- Cooking steps for a recipe. Never suggests throwing away a usable item.
local function cook(
	cloud: any,
	session: any,
	props: any,
	key: string,
	recipe: any,
	fallback: string,
	delay: Delay?
): Types.CoachSituation?
	local step = Cooking.Resolve(cloud, session, props, recipe, "None")
	if not step or step.waiting then
		return nil
	end
	local held = session.Hands[1]
	if word(step.id) == "discard" and not (held and held.Kind == "Burnt") then
		return nil
	end
	local cause = Causes[step.id] or Causes[word(step.id)]
	-- Dough's next station is named by the step itself.
	if step.id == "load_dough" then
		cause = "Dough goes to its next station"
	end
	return stuck(key, cause or fallback, step, delay)
end

local function seated(session: any, states: { [string]: boolean }): { { id: string, customer: any } }
	local list = {}
	for id, customer in session.Customers do
		if states[customer.State] and customer.TableId then
			list[#list + 1] = { id = id, customer = customer }
		end
	end
	table.sort(list, function(a, b): boolean
		local left, right = a.customer.OrderStartedAt or 0, b.customer.OrderStartedAt or 0
		return if left == right then a.id < b.id else left < right
	end)
	return list
end

local function guestFor(session: any, recipeId: string): (string?, any?)
	for _, entry in seated(session, { Waiting = true }) do
		if table.find(entry.customer.Orders, recipeId) then
			return entry.id, entry.customer
		end
	end
	return nil, nil
end

local function dirtySeat(session: any): (string?, number?)
	local ids = {}
	for id in session.Tables do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ids do
		for index, seat in session.Tables[id].Seats do
			if seat.Dirty and not seat.CustomerId then
				return id, index
			end
		end
	end
	return nil, nil
end

-- Orders are rolled when a guest spawns, so a guest still on the way or choosing already has one.
local function anyGuestWants(session: any, recipeId: string): boolean
	for _, customer in session.Customers do
		if customer.Kind ~= "Display" and UNSERVED[customer.State] and table.find(customer.Orders, recipeId) then
			return true
		end
	end
	return false
end

-- The one exception to keeping usable food: a dish or dough no guest ordered, with no free display
-- or kitchen window spot, only blocks the hands while guests wait. Until the player has binned such
-- an item once, the trash is shown quickly; afterwards they know where it is.
local function unwanted(cloud: any, session: any, props: any): Types.CoachSituation?
	local held = session.Hands[1]
	if not held or (held.Kind ~= "Dish" and held.Kind ~= "Dough") then
		return nil
	end
	if cloud.Tutorial.Actions.DisposedDish or session.Day.Phase ~= "Shift" then
		return nil
	end
	if #seated(session, { Waiting = true }) == 0 or anyGuestWants(session, held.Id) then
		return nil
	end
	if State.EmptyDisplay(session, props) or (props[WINDOW] and not session.Window[1]) then
		return nil
	end
	local recipe = Recipes:Get(held.Id)
	local name = if recipe then string.lower(recipe.name) else "dish"
	local step = State.Goal("discard_" .. held.Id, `Throw away the {name}`, "", "trash")
	return stuck("unwanted", "Nobody ordered this: bin it", step, "Waste")
end

-- Arrivals take only a free, clean chair and roam away otherwise, so during the shift every used
-- place costs a table guest; before opening it can wait.
local function guestsComing(session: any): boolean
	return session.Day.Phase == "Shift"
end

-- A station that waits for the player: the fire went out under a batch, or a batch is done.
local function stationNeeds(
	session: any,
	props: any,
	wanted: (station: any) -> boolean
): (string?, Types.TutorialGoal?)
	local ids = {}
	for id, station in session.Stations do
		if wanted(station) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	for _, id in ids do
		local step = Cooking.AtStation(session, props, id, session.Stations[id], false)
		if step and not step.waiting then
			return id, step
		end
	end
	return nil, nil
end

local function kitchenBusy(session: any): boolean
	for _, station in session.Stations do
		if station.State ~= "Idle" then
			return true
		end
	end
	return false
end

local function spill(session: any, props: any): Types.CoachSituation?
	local ids = {}
	for id in session.Spills do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local id = ids[1]
	if not id then
		return nil
	end
	local held = session.Hands[1]
	local broom = Buildings.Kinds.Broom.ToolId
	if held and held.Kind == "Tool" and held.Id == broom then
		local step = State.Goal("sweep_" .. id, "Sweep the puddle", "", id)
		return stuck("spill", "Sweep the spill with the broom", step, "Idle")
	end
	local free, ready = State.FreeHands(session, props, "", false)
	if not ready then
		return nil
	end
	local step = free or State.Goal("broom", "Take the broom", "", broom)
	return stuck("spill", "A spill on the floor: grab the broom", step, "Idle")
end

-- A quiet moment: make a menu dish that is not on the display yet, so counter guests can buy it.
local function bakeAhead(cloud: any, session: any, props: any, message: string, delay: Delay): Types.CoachSituation?
	if session.Hands[1] or kitchenBusy(session) or not State.EmptyDisplay(session, props) then
		return nil
	end
	local stocked = {}
	for _, recipeId in session.Display do
		stocked[recipeId] = true
	end
	local choice = session.Cooking.SelectedRecipeId
	if choice and (stocked[choice] or not table.find(session.Day.Menu, choice)) then
		choice = nil
	end
	if not choice then
		for _, recipeId in session.Day.Menu do
			if not stocked[recipeId] and Policy.CanPrepare(cloud, session, recipeId) then
				choice = recipeId
				break
			end
		end
	end
	local recipe = if choice then Recipes:Get(choice) else nil
	local result = if recipe then cook(cloud, session, props, "ahead", recipe, message, delay) else nil
	-- Before a recipe is chosen the idea matters more than the mixer; later steps keep their cause.
	if result and result.step and word(result.step.id) == "choose" then
		result.message = message
	end
	return result
end

--[[ Handling ]]--
function Assist.Resolve(cloud: any, session: any, props: { [string]: boolean }, now: number): Types.CoachSituation?
	local phase = session.Day.Phase
	if phase ~= "Shift" and phase ~= "Prep" then
		return nil
	end
	local held = session.Hands[1]

	if held and held.Kind == "Burnt" then
		local step = State.FreeHands(session, props, "", false)
		return stuck("burnt", "Burnt food can't be served", step)
	end

	local urgent = Cooking.Urgent(session, props, false)
	if urgent and not urgent.waiting then
		urgent.urgent = nil
		return {
			key = `urgent:{urgent.id}`,
			message = "Take it out before it burns",
			step = urgent,
			delay = "Urgent",
		}
	end

	local waste = unwanted(cloud, session, props)
	if waste then
		return waste
	end

	-- A seated guest close to walking out outranks everything that can wait.
	for _, entry in seated(session, { Waiting = true }) do
		local customer = entry.customer
		local endsAt = customer.PatienceEndsAt or 0
		if customer.TutorialProtected or endsAt <= 0 or endsAt - now > Config.Coach.HurrySeconds then
			continue
		end
		local message = "Hurry: a guest is about to leave"
		if held and held.Kind == "Dish" and table.find(customer.Orders, held.Id) then
			local step = State.SeatGoal(
				"serve",
				"Serve the guest who ordered this",
				"",
				customer.TableId,
				customer.SeatIndex or 1
			)
			return stuck(`hurry:{entry.id}`, message, step, "Urgent")
		end
		local recipe = Recipes:Get(customer.Orders[1])
		local result = if recipe then cook(cloud, session, props, `hurry:{entry.id}`, recipe, message, "Urgent") else nil
		if result then
			result.message = message
			return result
		end
	end

	if held and held.Kind == "Dish" then
		local guestId, customer = guestFor(session, held.Id)
		if guestId and customer then
			local step = State.SeatGoal(
				"serve",
				"Serve the guest who ordered this",
				"",
				customer.TableId,
				customer.SeatIndex or 1
			)
			return stuck(`serve:{guestId}`, "A guest is waiting for this dish", step)
		end
		local display = State.EmptyDisplay(session, props)
		if display then
			local step = State.Goal("store_dish", "Set this dish on the display", "", display)
			return stuck("display", "Nobody ordered this; try the display", step)
		end
	end

	if held and held.Kind == "Dough" then
		local recipe = Recipes:Get(held.Id)
		if recipe then
			return cook(cloud, session, props, "dough", recipe, "Dough goes to its next station")
		end
	end

	-- Without fire a loaded oven never bakes; a burnt batch blocks its station.
	local _, fire = stationNeeds(session, props, function(station: any): boolean
		local kind = Buildings.Kinds[station.Kind]
		return kind ~= nil
			and kind.UsesFuel == true
			and (station.State == "Loaded" or (station.State == "Cooking" and (station.HeatPausedAt or 0) > 0))
	end)
	if fire then
		return stuck("fire", "The oven fire went out", fire)
	end
	local _, blocked = stationNeeds(session, props, function(station: any): boolean
		return station.State == "Burnt"
	end)
	if blocked then
		return stuck("burnt_station", "Burnt food is blocking the oven", blocked)
	end

	for _, entry in seated(session, { Choosing = true }) do
		local customer = entry.customer
		if now < (customer.ChoosingEndsAt or 0) then
			continue
		end
		local step = State.SeatGoal("take_order", "Take the guest's order", "", customer.TableId, customer.SeatIndex or 1)
		return stuck(`order:{entry.id}`, "A guest is ready to order", step)
	end

	for _, entry in seated(session, { Waiting = true }) do
		local recipe = Recipes:Get(entry.customer.Orders[1])
		if recipe then
			local result = cook(cloud, session, props, `guest:{entry.id}`, recipe, `A guest is waiting for {recipe.name}`)
			if result then
				return result
			end
		end
	end

	local _, finished = stationNeeds(session, props, function(station: any): boolean
		return station.State == "Ready"
	end)
	if finished then
		return stuck("ready", "Your batch is ready to collect", finished)
	end

	local tableId, seatIndex = dirtySeat(session)
	if tableId and seatIndex then
		local step = State.SeatGoal("clean_table", "Clean the used place", "", tableId, seatIndex)
		if guestsComing(session) then
			return stuck("clean", "New guests need a clean seat", step)
		end
		return stuck("clean", "Clean used places for the next guests", step, "Idle")
	end

	local floor = spill(session, props)
	if floor then
		return floor
	end

	if phase == "Shift" then
		if #seated(session, { Waiting = true, Choosing = true }) > 0 then
			return nil
		end
		return bakeAhead(cloud, session, props, "Quiet moment? Bake for the display", "Idle")
	end

	-- Cooking ahead during preparation is progress, not hesitation.
	if held or kitchenBusy(session) then
		return nil
	end
	if not next(session.Display) then
		local ahead = bakeAhead(cloud, session, props, "Bake a dish ahead, then open", "Prep")
		if ahead then
			return ahead
		end
	end
	local step = State.Gui("open", "Open your bakery", "", OPEN_CLOCK)
	return { key = "prep:open", message = "Ready? The clock opens your bakery", step = step, delay = "Prep" }
end

-- Evening plans after the first one: report, then 3 to 5 recipes, then Next Day.
function Assist.Summary(session: any, page: string): Types.CoachSituation?
	local count = #session.Day.NextMenu
	if page == "Report" then
		local step = State.Gui("open_next_menu", "Open the menu", "", MENU_BUTTON)
		return { key = "summary:report", message = "Next, plan tomorrow's menu", step = step, delay = "Summary" }
	end
	if page ~= "Inventory" then
		return nil
	end
	if count < DayCycle.MenuMin or count > DayCycle.MenuMax then
		return {
			key = `summary:pick:{count}`,
			message = "Pick 3 to 5 recipes for tomorrow",
			anchor = { kind = "Gui", id = MENU_GRID },
			delay = "Summary",
		}
	end
	local step = State.Gui("next_day", "Start the next day", "", NEXT_DAY_BUTTON)
	return { key = "summary:next", message = "Menu ready? Start the next day", step = step, delay = "Summary" }
end

return Assist
