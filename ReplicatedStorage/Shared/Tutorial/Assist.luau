--!strict
-- What a helper would suggest right now, after the introduction. Each situation names its cause in
-- a few words; the step is the concrete action. Pure reads: timing and display live in Coach.

--[[ Modules ]]--
local Cooking = require(script.Parent.Cooking)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Constants ]]--
local OPEN_CLOCK = "UI.HUD.Time"

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

local function stuck(key: string, message: string, step: Types.TutorialGoal?): Types.CoachSituation?
	if not step or step.waiting then
		return nil
	end
	return { key = `{key}:{step.id}`, message = message, step = step, delay = "Stuck" }
end

-- Cooking steps for a recipe. Never suggests throwing away a usable item.
local function cook(
	cloud: any,
	session: any,
	props: any,
	key: string,
	recipe: any,
	fallback: string
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
	return stuck(key, cause or fallback, step)
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

local function guestsComing(session: any): boolean
	for _, customer in session.Customers do
		if customer.State == "Queued" or customer.State == "Arriving" then
			return true
		end
	end
	return false
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

	local tableId, seatIndex = dirtySeat(session)
	if tableId and seatIndex and guestsComing(session) then
		local step = State.SeatGoal("clean_table", "Clean the used place", "", tableId, seatIndex)
		return stuck("clean", "New guests need a clean seat", step)
	end

	local busy = false
	for _, station in session.Stations do
		busy = busy or station.State ~= "Idle"
	end
	-- Cooking ahead during preparation is progress, not hesitation.
	if phase == "Prep" and not held and not busy then
		local step = State.Gui("open", "Open your bakery", "", OPEN_CLOCK)
		return { key = "prep:open", message = "Ready? The clock opens your bakery", step = step, delay = "Prep" }
	end
	return nil
end

return Assist
