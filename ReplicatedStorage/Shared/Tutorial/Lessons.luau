--!strict
-- Optional lessons appear at their first useful moment and can always be dismissed.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local Cooking = require(script.Parent.Cooking)
local Garden = require(script.Parent.Parent.Configs.Garden)
local Ingredients = require(script.Parent.Parent.Configs.Registries.Ingredients)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Tables ]]--
local Lessons = {}

--[[ Private Functions ]]--
local function wanted(cloud: any, topic: string): boolean
	local lessons = cloud.Tutorial.Lessons
	return not lessons[topic] and not lessons["Dismissed:" .. topic]
end

local function floor(cloud: any, session: any, props: any): Types.TutorialGoal?
	if not wanted(cloud, "Floor") then
		return nil
	end
	local held = session.Hands[1]
	if cloud.Tutorial.Actions.Mopped and held and held.Id == Buildings.Kinds.Broom.ToolId then
		return State.Goal(
			"return_broom",
			"Return the broom",
			"A clean floor is ready for work. Put the broom back to free your hand.",
			held.Id
		)
	end
	for id in session.Spills do
		if held and held.Id == Buildings.Kinds.Broom.ToolId then
			return State.Goal(
				"sweep_" .. id,
				"Sweep the puddle",
				"Approach the spill with the broom and use Clean once.",
				id
			)
		end
		return State.FreeHands(session, props, "Free your hand so you can pick up the broom.")
			or State.Goal(
				"broom",
				"Take the broom",
				"Cooking sometimes leaves a puddle. A broom lets you clean it.",
				Buildings.Kinds.Broom.ToolId
			)
	end
	return nil
end

local function garden(cloud: any, session: any, props: any): Types.TutorialGoal?
	if not wanted(cloud, "Garden") then
		return nil
	end
	local ids = {}
	for id, source in Garden.Sources do
		if (cloud.Base.Upgrades[source.Upgrade] or 0) > 0 and not cloud.Tutorial.Actions["Harvest:" .. id] then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local id = ids[1]
	return if id then Cooking.Garden(cloud, session, props, id, Garden.Sources[id]) else nil
end

--[[ Handling ]]--
function Lessons.Summary(session: any, page: string): Types.TutorialGoal
	if page ~= "Inventory" then
		local target = if page == "Upgrades"
			then "Upgrades.MainFrame.Header.DayReport"
			else "Report.MainFrame.Header.Buttons.Menu"
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
		if ready then "Inventory.MainFrame.Header.TopSection.NextDay" else "Inventory.MainFrame.Container.Content"
	)
	goal.topic = "NextDay"
	return goal
end

function Lessons.Resolve(cloud: any, session: any, props: any, page: string): Types.TutorialGoal?
	if page == "Upgrades" and wanted(cloud, "Upgrades") then
		local goal = State.Gui(
			"upgrades",
			"See what this upgrade changes",
			"The selected upgrade's name, price and result are shown here. Buying is optional.",
			"Upgrades.MainFrame.Main.Bottom"
		)
		goal.topic = "Upgrades"
		return goal
	end
	if page ~= "None" then
		return nil
	end
	local held = session.Hands[1]
	if held and held.Kind == "Burnt" and not cloud.Tutorial.Actions.DisposedBurnt and wanted(cloud, "Cooking") then
		local goal =
			State.FreeHands(session, props, "Burnt food cannot be served. Throw it away, then make a fresh batch.")
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
			local goal = Cooking.AtStation(session, props, id, station)
			if goal then
				goal.topic = "Cooking"
				goal.recipeId = station.RecipeId
				return goal
			end
		end
	end
	if wanted(cloud, "Display") and held and held.Kind == "Dish" then
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
	if wanted(cloud, "Cart") and props.rail_cart then
		local goal = nil
		if held and held.Kind == "Ingredient" and not Ingredients:IsInfinite(held.Id) then
			goal = State.Goal(
				"cart_load",
				"Send this ingredient to the kitchen",
				"Load the cart; it makes the trip and returns by itself.",
				"rail_cart"
			)
		elseif #cloud.GardenCart.Queue > 0 then
			goal = State.FreeHands(session, props, "Free your hand before collecting a delivery.")
				or State.Goal(
					"cart_take",
					"Collect your kitchen delivery",
					"The rail output stores delivered produce. Take one ingredient at a time.",
					"rail_output"
				)
		end
		if goal then
			goal.topic = "Cart"
			return goal
		end
	end
	local gardenGoal = garden(cloud, session, props)
	if gardenGoal then
		gardenGoal.topic = "Garden"
	end
	return gardenGoal
end

return Lessons
