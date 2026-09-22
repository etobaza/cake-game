--!strict
-- One goal, selected by priority. Live kitchen state supplies recovery routes after any interruption.

--[[ Modules ]]--
local Config = require(script.Parent.Parent.Configs.Tutorial)
local Cooking = require(script.Parent.Cooking)
local Lessons = require(script.Parent.Lessons)
local Policy = require(script.Parent.Parent.TutorialPolicy)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Tables ]]--
local Scenario = {}

--[[ Private Functions ]]--
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

local function serve(session: any, now: number): Types.TutorialGoal
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
	if now - customer.OrderStartedAt < Config.OrderPreviewSeconds then
		local goal = State.Goal(
			"order_card",
			"This is your guest's order",
			"The card shows the dish and table.seat number. Bring the matching dish to that place.",
			nil
		)
		goal.target = { kind = "Order", id = context.GuestId }
		goal.waiting = true
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
function Scenario.Resolve(cloud: any, session: any, props: any, page: string, now: number): Types.TutorialGoal?
	local active = Policy.IsActive(cloud)
	if session.Day.Phase == "Summary" then
		return if not cloud.Tutorial.Lessons.NextDay and not cloud.Tutorial.Lessons["Dismissed:NextDay"]
			then Lessons.Summary(session, page)
			else nil
	end
	local teachOven = session.Tutorial.OvenLesson
		and not cloud.Tutorial.Actions.CollectedOvenDish
		and not cloud.Tutorial.Lessons["Dismissed:Cooking"]
	local urgent = if active or teachOven then Cooking.Urgent(session, props) else nil
	if urgent then
		if not active then
			urgent.topic = "Cooking"
		end
		if page ~= "None" then
			local goal = State.Gui(
				"close_for_oven",
				"Your baked dish is ready",
				"Close this page and collect the dish before it burns.",
				page .. ".MainFrame.Header.Exit"
			)
			goal.urgent = true
			return goal
		end
		return urgent
	end
	if not active then
		return Lessons.Resolve(cloud, session, props, page)
	end
	if page == "Upgrades" then
		return Lessons.Resolve(cloud, session, props, page)
	end
	local context = session.Tutorial
	if context.Stage == "Clean" then
		return clean(session, now)
	end
	local customer = session.Customers[context.GuestId]
	local held = session.Hands[1]
	local recipe = Recipes:Get(Policy.Recipe(session))
	if not recipe then
		return nil
	end
	if
		customer
		and (
			customer.State == "Choosing"
			or (customer.State == "Waiting" and now - customer.OrderStartedAt < Config.OrderPreviewSeconds)
		)
	then
		local goal = serve(session, now)
		goal.recipeId = recipe.id
		return goal
	end
	local goal = Cooking.Resolve(cloud, session, props, recipe, page)
	if goal then
		goal.recipeId = goal.recipeId or recipe.id
		return goal
	end
	if held and held.Kind == "Dish" then
		local serving = serve(session, now)
		serving.recipeId = held.Id
		return serving
	end
	return nil
end

return Scenario
