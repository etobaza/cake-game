--!strict
-- Newly unlocked dishes the player can always supply but left off tomorrow's menu. Pure reads shared by
-- the first evening's lesson, the evening coach and the Menu tab's alert mark.

--[[ Modules ]]--
local DayCycle = require(script.Parent.Parent.Configs.DayCycle)
local RecipeRequirements = require(script.Parent.Parent.RecipeRequirements)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Constants ]]--
local MENU_BUTTON = "BakeryMenu.MainFrame.Header.Buttons.Menu"
-- MenuHandler names each grid cell after the recipe it shows.
local MENU_GRID = "Inventory.MainFrame.Container.Content"

--[[ Tables ]]--
local MenuPlan = {}

--[[ Handling ]]--
--- The newest such dish while tomorrow's menu still has room. Only dishes still new from a level-up
--- count, so a menu the player keeps short on purpose is not nagged every evening; starter dishes
--- are marked new at grant too, so level 1 is left out.
function MenuPlan.Missing(cloud: any, session: any): Recipes.RecipeEntry?
	local menu = session.Day.NextMenu
	if #menu >= DayCycle.MenuMax then
		return nil
	end
	local stations: { [string]: boolean } = {}
	for _, station in session.Stations do
		stations[station.Kind] = true
	end
	local best: Recipes.RecipeEntry? = nil
	for _, recipe in Recipes:GetAvailable(cloud.Level or 1) do
		local newUntil = cloud.NewRecipeUntilDay[recipe.id]
		if
			recipe.unlockLevel <= 1
			or not newUntil
			or cloud.Day > newUntil
			or table.find(menu, recipe.id)
			or not stations[recipe.station]
			or not RecipeRequirements.IsObtainable(recipe, cloud.Base.Upgrades)
		then
			continue
		end
		local newer = not best
			or recipe.unlockLevel > best.unlockLevel
			or (recipe.unlockLevel == best.unlockLevel and recipe.order < best.order)
		if newer then
			best = recipe
		end
	end
	return best
end

--- The press that adds `recipe`: its cell while the menu is open, the Menu tab before that.
function MenuPlan.Step(recipe: Recipes.RecipeEntry, page: string): Types.TutorialGoal
	local goal = if page == "Inventory"
		then State.Gui(
			`menu_add_{recipe.id}`,
			"Add {" .. recipe.name .. "}",
			"Tap it to put it on tomorrow's menu.",
			`{MENU_GRID}.{recipe.id}`
		)
		else State.Gui("menu_open", "Open the {menu}", "New dishes go on tomorrow's menu here.", MENU_BUTTON)
	if page == "Inventory" and goal.target then
		goal.target.control = "Scroll"
	end
	goal.recipeId = recipe.id
	return goal
end

--- Evening coaching: from the report to the dish's cell, at once.
function MenuPlan.Summary(cloud: any, session: any, page: string): Types.CoachSituation?
	if page ~= "Report" and page ~= "Inventory" then
		return nil
	end
	local recipe = MenuPlan.Missing(cloud, session)
	if not recipe then
		return nil
	end
	return {
		key = `menu:{recipe.id}:{page}`,
		message = `Add {recipe.name} to tomorrow's menu`,
		step = MenuPlan.Step(recipe, page),
		delay = "Feature",
	}
end

return MenuPlan
