--!strict
-- Optional lessons appear at their first useful moment, once, and never ask the player
-- to discard useful items or leave a waiting guest for a detour.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local Cooking = require(script.Parent.Cooking)
local Garden = require(script.Parent.Parent.Configs.Garden)
local GardenSource = require(script.Parent.Parent.GardenSource)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Constants ]]--
local GARDEN_ROOM = "Garden"
-- Orders are rolled when a guest spawns, so a guest still on the way or choosing already has one.
local UNSERVED = { Queued = true, Arriving = true, Choosing = true, Waiting = true }

--[[ Tables ]]--
local Lessons = {}

--[[ Private Functions ]]--
-- A dish a table guest still has to receive belongs at their table, not on the display.
local function ordered(session: any, recipeId: string): boolean
	for _, customer in session.Customers do
		if customer.Kind ~= "Display" and UNSERVED[customer.State] and table.find(customer.Orders, recipeId) then
			return true
		end
	end
	return false
end

local function wanted(cloud: any, topic: string): boolean
	local lessons = cloud.Tutorial.Lessons
	return not lessons[topic] and not lessons["Dismissed:" .. topic]
end

-- Produce harvested in the garden itself. Milk and eggs come out of kitchen baskets, so the cart
-- has nothing to carry for them.
local function grownInGarden(ingredientId: string): boolean
	local _, source = GardenSource.Find(ingredientId)
	return source ~= nil and source.OutputPath == nil
end

local function delivered(cloud: any): boolean
	for _, cart in cloud.GardenCart.Carts do
		if cart.Arrived then
			return true
		end
	end
	return false
end

-- The cart is taught in two moments: loading garden produce while standing in the garden, then
-- collecting the first delivery once it has arrived. Carrying produce indoors by hand after the
-- first prompt retires the lesson (TutorialHandler sends the dismissal).
local function cart(cloud: any, session: any, props: any, room: string?): Types.TutorialGoal?
	if not wanted(cloud, "Cart") or not props.rail_cart then
		return nil
	end
	if not cloud.Tutorial.Actions.LoadedCart then
		local held = session.Hands[1]
		if room ~= GARDEN_ROOM or not held or held.Kind ~= "Ingredient" or not grownInGarden(held.Id) then
			return nil
		end
		return State.Goal(
			"cart_load",
			"Send this ingredient to the kitchen",
			"Load the cart; it makes the trip and returns by itself.",
			"rail_cart"
		)
	end
	if not delivered(cloud) then
		return nil
	end
	-- A busy hand waits: an arrival is no reason to send the player off to return a tool.
	local _, ready = State.FreeHands(session, props, "", false)
	if not ready then
		return nil
	end
	return State.Goal(
		"cart_take",
		"Collect your kitchen delivery",
		"The rail output stores delivered produce. Take one ingredient at a time.",
		"rail_output"
	)
end

local function floor(cloud: any, session: any, props: any): Types.TutorialGoal?
	if not wanted(cloud, "Floor") then
		return nil
	end
	local held = session.Hands[1]
	local holdingBroom = held ~= nil and held.Id == Buildings.Kinds.Broom.ToolId
	-- Spills come first: a lifetime Mopped flag must not send the broom back while a puddle remains.
	for id in session.Spills do
		if holdingBroom then
			local goal = State.Goal(
				"sweep_" .. id,
				"Sweep the {spill}",
				"Walk up to the glowing spill with the broom and press Sweep.",
				id
			)
			goal.highlight = true
			return goal
		end
		-- A busy hand postpones this optional lesson instead of sending useful items to the trash.
		local free, ready = State.FreeHands(session, props, "Free your hand so you can pick up the broom.", false)
		if not ready then
			return free
		end
		return State.Goal(
			"broom",
			"Take the broom",
			"Cooking sometimes leaves a puddle. A broom lets you clean it.",
			Buildings.Kinds.Broom.ToolId
		)
	end
	if cloud.Tutorial.Actions.Mopped and holdingBroom then
		return State.Goal(
			"return_broom",
			"Floor clean! Return the broom",
			"Put the broom back on its rack to free your hand.",
			Buildings.Kinds.Broom.ToolId
		)
	end
	return nil
end

local function garden(cloud: any, session: any, props: any): Types.TutorialGoal?
	if not wanted(cloud, "Garden") then
		return nil
	end
	-- The garden pulls the player away from the kitchen, so it waits for the untimed morning
	-- unless the player is already working there with the watering can.
	local held = session.Hands[1]
	local watering = held and held.Kind == "Tool" and held.Id == Buildings.Kinds.WateringCan.ToolId
	if session.Day.Phase ~= "Prep" and not watering then
		return nil
	end
	local ids = {}
	for id, source in Garden.Sources do
		if (cloud.Base.Upgrades[source.Upgrade] or 0) > 0 and not cloud.Tutorial.Actions["Harvest:" .. id] then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	-- Growing produce needs nothing from the player; a waiting goal here would only silence the
	-- other guides for the whole morning.
	for _, id in ids do
		local goal = Cooking.Garden(cloud, session, props, id, Garden.Sources[id], false)
		if goal and not goal.waiting then
			return goal
		end
	end
	return nil
end

--[[ Handling ]]--
function Lessons.Summary(session: any, page: string): Types.TutorialGoal
	if page ~= "Inventory" then
		local target = "BakeryMenu.MainFrame.Header.Buttons.Menu"
		local goal = State.Gui(
			"open_next_menu",
			"Plan tomorrow's menu",
			"Review the report, then open Next Menu. There is no time limit.",
			target
		)
		goal.topic = "NextDay"
		return goal
	end
	local count = #session.Day.NextMenu
	local ready = count >= 3 and count <= 5
	local goal = State.Gui(
		"next_menu",
		if ready then "Your next menu is ready" else "Choose 3–5 recipes for tomorrow",
		"Select recipes you want to sell. Next Day saves the menu and starts a new preparation period with no timer.",
		if ready then "BakeryMenu.MainFrame.Header.Buttons.NextDay" else "Inventory.MainFrame.Container.Content"
	)
	goal.topic = "NextDay"
	return goal
end

-- Whether the cart lesson is waiting for its first load while the player carries garden produce
-- somewhere other than the garden: they chose to walk it in by hand.
function Lessons.CarriedPastCart(cloud: any, session: any, props: any, room: string?): boolean
	local held = session.Hands[1]
	return wanted(cloud, "Cart")
		and props.rail_cart == true
		and not cloud.Tutorial.Actions.LoadedCart
		and room ~= nil
		and room ~= GARDEN_ROOM
		and held ~= nil
		and held.Kind == "Ingredient"
		and grownInGarden(held.Id)
end

function Lessons.Resolve(cloud: any, session: any, props: any, page: string, room: string?): Types.TutorialGoal?
	if page ~= "None" then
		return nil
	end
	local held = session.Hands[1]
	if held and held.Kind == "Burnt" and not cloud.Tutorial.Actions.DisposedBurnt and wanted(cloud, "Cooking") then
		local goal = State.FreeHands(
			session,
			props,
			"Burnt food cannot be served. Throw it away, then make a fresh batch.",
			false
		)
		if goal then
			goal.topic = "Cooking"
		end
		return goal
	end
	local floorGoal = floor(cloud, session, props)
	if floorGoal then
		floorGoal.topic = "Floor"
		return floorGoal
	end
	if session.Tutorial.OvenLesson and not cloud.Tutorial.Actions.CollectedOvenDish and wanted(cloud, "Cooking") then
		for id, station in session.Stations do
			if station.Kind ~= "Oven" or station.State == "Idle" then
				continue
			end
			local goal = Cooking.AtStation(session, props, id, station, false)
			if goal then
				goal.topic = "Cooking"
				goal.recipeId = station.RecipeId
				return goal
			end
		end
	end
	if wanted(cloud, "Display") and held and held.Kind == "Dish" and not ordered(session, held.Id) then
		local display = State.EmptyDisplay(session, props)
		if display then
			local goal = State.Goal(
				"display_lesson",
				"Try stocking the display",
				"Counter guests buy dishes here themselves. You can take a dish back whenever you need it.",
				display
			)
			goal.recipeId = held.Id
			goal.topic = "Display"
			return goal
		end
	end
	local cartGoal = cart(cloud, session, props, room)
	if cartGoal then
		cartGoal.topic = "Cart"
		return cartGoal
	end
	local gardenGoal = garden(cloud, session, props)
	if gardenGoal then
		gardenGoal.topic = "Garden"
	end
	return gardenGoal
end

return Lessons
