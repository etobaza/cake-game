--!strict
-- One goal, selected by priority. Live kitchen state supplies recovery routes after any interruption.

--[[ Modules ]]--
local Config = require(script.Parent.Parent.Configs.Tutorial)
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local Cooking = require(script.Parent.Cooking)
local Lessons = require(script.Parent.Lessons)
local Navigation = require(script.Parent.Navigation)
local Policy = require(script.Parent.Parent.TutorialPolicy)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Tables ]]--
local Scenario = {}

--[[ Private Functions ]]--
local function sweep(cloud: any, session: any, props: any): Types.TutorialGoal?
	local held = session.Hands[1]
	local broom = Buildings.Kinds.Broom.ToolId
	local spills = {}
	for id in session.Spills do
		spills[#spills + 1] = id
	end
	table.sort(spills)
	if not spills[1] then
		-- Only an accepted sweep earns the return step. A broom taken before the spill appeared
		-- waits here until there is something to sweep.
		if held and held.Kind == "Tool" and held.Id == broom and cloud.Tutorial.Actions.Mopped then
			return State.Goal(
				"intro_return_broom",
				"Floor clean! Return the {broom}",
				"Put the broom back on its rack to free your hands for baking.",
				broom
			)
		end
		local goal = State.Goal(
			"intro_preparing",
			"Getting your bakery ready…",
			"Your first task will appear in a moment.",
			nil
		)
		goal.waiting = true
		return goal
	end
	if held and held.Kind == "Tool" and held.Id == broom then
		local goal = State.Goal(
			"intro_sweep_" .. spills[1],
			"Sweep the {dough spill}",
			"Walk up to the glowing spill and press Sweep. A clean floor keeps you fast.",
			spills[1]
		)
		goal.highlight = true
		return goal
	end
	local free, ready = State.FreeHands(session, props, "Free your hand to take the broom.", true)
	if not ready then
		return free
	end
	return State.Goal(
		"intro_broom",
		"First, pick up the {broom}",
		"Follow the arrows to the broom rack. Let's tidy the kitchen before your first bake.",
		broom
	)
end

local function clean(session: any, now: number): Types.TutorialGoal
	local context = session.Tutorial
	local customer = session.Customers[context.GuestId]
	if customer then
		local paid = now - context.SaleAt < Config.SuccessSeconds
		local title = if paid
			then string.format("First sale! +$%.2f", context.LastSale)
			else "Your guest is enjoying the food"
		local goal = State.SeatGoal(
			"eating",
			title,
			"Payment and XP are already yours. Their place will need cleaning when they finish eating.",
			context.TableId,
			context.SeatIndex
		)
		goal.waiting = true
		return goal
	end
	return State.SeatGoal(
		"clean_table",
		"Clean the used place",
		"Clear this place so the next guest can sit down. No broom is needed for a table.",
		context.TableId,
		context.SeatIndex
	)
end

-- The first order card is shown until the player taps it or acknowledges it in the bubble. Only a
-- gamepad, which cannot tap the card, also moves on after the fallback time.
local function previewing(session: any, customer: any, now: number, facts: Types.TutorialContext): boolean
	return customer.State == "Waiting"
		and facts.orderSeen ~= session.Tutorial.GuestId
		and (not facts.gamepad or now - customer.OrderStartedAt < Config.OrderPreviewSeconds)
end

local function serve(session: any, now: number, facts: Types.TutorialContext): Types.TutorialGoal
	local context = session.Tutorial
	local customer = session.Customers[context.GuestId]
	if session.Day.Phase == "Prep" then
		return State.Gui(
			"open",
			"Open your bakery",
			"Press the clock when you are ready. Your first guest has all the time they need.",
			"UI.HUD.Time"
		)
	end
	if not customer or customer.State == "Arriving" or customer.State == "Queued" then
		local goal = State.Goal(
			"guest_arriving",
			"Your first guest is on the way…",
			"They will take a seat. The clock stays at 08:00 during this first order.",
			nil
		)
		goal.waiting = true
		return goal
	end
	if customer.State == "Choosing" then
		return State.SeatGoal(
			"take_order",
			"Take your guest's order",
			"Approach this seat and use Take order. The order card shows the dish and seat number.",
			customer.TableId,
			customer.SeatIndex or 1
		)
	end
	if previewing(session, customer, now, facts) then
		local goal = State.Goal(
			"order_card",
			"Tap your guest's {order card}",
			"It shows the dish they want. Its number is the seat to bring that dish to.",
			nil
		)
		goal.target = { kind = "Order", id = context.GuestId }
		return goal
	end
	return State.SeatGoal(
		"serve",
		"Serve your guest",
		"Carry the ordered dish to this place and use Serve. They pay as soon as you hand it over.",
		customer.TableId,
		customer.SeatIndex or 1
	)
end

--[[ Handling ]]--
local function resolve(
	cloud: any,
	session: any,
	props: any,
	page: string,
	now: number,
	facts: Types.TutorialContext
): Types.TutorialGoal?
	local active = Policy.IsActive(cloud)
	if session.Day.Phase == "Summary" then
		return if not cloud.Tutorial.Lessons.NextDay and not cloud.Tutorial.Lessons["Dismissed:NextDay"]
			then Lessons.Summary(session, page)
			else nil
	end
	local teachOven = session.Tutorial.OvenLesson
		and not cloud.Tutorial.Actions.CollectedOvenDish
		and not cloud.Tutorial.Lessons["Dismissed:Cooking"]
	local urgent = if active or teachOven then Cooking.Urgent(session, props, active) else nil
	if urgent then
		if not active then
			urgent.topic = "Cooking"
		end
		if page ~= "None" then
			local goal = State.Close(
				"close_for_oven",
				"Your baked dish is ready",
				"Close this page and collect the dish before it burns.",
				page
			)
			goal.urgent = true
			return goal
		end
		return urgent
	end
	if not active then
		return Lessons.Resolve(cloud, session, props, page, facts.room)
	end
	local context = session.Tutorial
	if context.Stage == "Sweep" then
		return sweep(cloud, session, props)
	end
	if context.Stage == "Clean" then
		return clean(session, now)
	end
	local customer = session.Customers[context.GuestId]
	local held = session.Hands[1]
	local recipeId = Policy.Recipe(session)
	local recipe = recipeId and Recipes:Get(recipeId)
	if not recipe then
		return nil
	end
	if
		customer
		and (
			customer.State == "Choosing"
			or previewing(session, customer, now, facts)
		)
	then
		local goal = serve(session, now, facts)
		goal.recipeId = recipe.id
		return goal
	end
	local goal = Cooking.Resolve(cloud, session, props, recipe, page)
	if goal then
		goal.recipeId = goal.recipeId or recipe.id
		return goal
	end
	if held and held.Kind == "Dish" then
		local serving = serve(session, now, facts)
		serving.recipeId = held.Id
		return serving
	end
	return nil
end

function Scenario.Resolve(
	cloud: any,
	session: any,
	props: any,
	page: string,
	now: number,
	facts: Types.TutorialContext?
): Types.TutorialGoal?
	local known: Types.TutorialContext = facts or {}
	return Navigation.Resolve(resolve(cloud, session, props, page, now, known), page, known.canClose ~= false)
end

return Scenario
