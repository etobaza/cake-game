--!strict
-- Bought features the player has not used yet. Pure reads over saved flags and live kitchen data:
-- the server marks `Use:` / `Due:` / `Feature:` flags, these functions only decide what to explain.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local Config = require(script.Parent.Parent.Configs.Tutorial)
local Cooking = require(script.Parent.Cooking)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Types ]]--
export type Feature = typeof(Config.Features[1])

--[[ Constants ]]--
local MENU_BUTTON = "BakeryMenu.MainFrame.Header.Buttons.Menu"
local MENU_GRID = "Inventory.MainFrame.Container.Content"
local ASSISTANT_PLATE = "Inventory.MainFrame.Header.TopSection.Assistant"

--[[ Tables ]]--
local Features = {}

--[[ Private Functions ]]--
local function find(id: string): Feature?
	for _, feature in Config.Features do
		if feature.id == id then
			return feature
		end
	end
	return nil
end

local function onMenu(menu: { string }, station: string): boolean
	for _, recipeId in menu do
		local recipe = Recipes:Get(recipeId)
		if recipe and recipe.station == station then
			return true
		end
	end
	return false
end

local function unlocked(cloud: any, station: string): string?
	for _, recipe in Recipes:GetUnlockedAt(cloud.Level or 1) do
		if recipe.station == station then
			return recipe.name
		end
	end
	return nil
end

-- A dish a seated guest still waits for.
local function ordered(session: any, recipeId: string): boolean
	for _, customer in session.Customers do
		if customer.State == "Waiting" and table.find(customer.Orders, recipeId) then
			return true
		end
	end
	return false
end

local function situation(feature: Feature, key: string, message: string, step: Types.TutorialGoal?): Types.CoachSituation
	return { key = `feature:{feature.id}:{key}`, message = message, step = step, delay = "Feature" }
end

--[[ Handling ]]--
function Features.Owned(cloud: any, feature: Feature): boolean
	return (cloud.Base.Upgrades[feature.upgrade] or 0) > 0
end

function Features.Used(cloud: any, feature: Feature): boolean
	if cloud.Tutorial.Actions[`Use:{feature.id}`] then
		return true
	end
	return feature.task == true and (cloud.AssistantTask or "None") ~= "None"
end

-- Owned, unused through a whole shift, and not yet retired.
function Features.Due(cloud: any, feature: Feature): boolean
	local lessons = cloud.Tutorial.Lessons
	return Features.Owned(cloud, feature)
		and lessons[`Due:{feature.id}`] == true
		and not lessons[`Feature:{feature.id}`]
		and not Features.Used(cloud, feature)
end

-- Server: does this accepted building action count as using the feature?
function Features.Matches(feature: Feature, action: string, buildingId: string): boolean
	local prefix = feature.prefix
	if not prefix or (feature.actions and not feature.actions[action]) then
		return false
	end
	local name, index = string.match(buildingId, "^(.-)_(%d+)$")
	return name == prefix and (tonumber(index) or 0) >= (feature.minIndex or 1)
end

-- The evening plan: features that need tomorrow's menu or the assistant's job.
function Features.Summary(cloud: any, session: any, page: string): Types.CoachSituation?
	if page ~= "Inventory" and page ~= "Report" then
		return nil
	end
	local onReport = page == "Report"
	local assistant = find("assistant")
	if assistant and Features.Due(cloud, assistant) then
		local result = situation(assistant, page, "Give your assistant a job for tomorrow", nil)
		result.step = if onReport
			then State.Gui("coach_menu", "Open the menu to plan tomorrow", "", MENU_BUTTON)
			else State.Gui("coach_assistant", "Choose your assistant's job", "", ASSISTANT_PLATE)
		return result
	end
	for _, feature in Config.Features do
		local station = feature.station
		if not station or not Features.Due(cloud, feature) or onMenu(session.Day.NextMenu, station) then
			continue
		end
		local name = if station == "Coffee" then "Coffee" else unlocked(cloud, station)
		if not name then
			continue
		end
		local result = situation(feature, page, `Add {name} to tomorrow's menu`, nil)
		if onReport then
			result.step = State.Gui("coach_menu", "Open the menu to plan tomorrow", "", MENU_BUTTON)
		else
			-- Any recipe card can be chosen, so only the grid anchors this message.
			result.anchor = { kind = "Gui", id = MENU_GRID }
		end
		return result
	end
	return nil
end

-- Between-days introductions for the untimed preparation, one short line per due feature.
function Features.Intros(cloud: any, session: any): { Types.CoachSituation }
	local list = {}
	for _, feature in Config.Features do
		if not Features.Due(cloud, feature) or feature.task then
			continue
		end
		-- A station feature only helps today when its recipe is on today's menu.
		if feature.station and not onMenu(session.Day.Menu, feature.station) then
			continue
		end
		list[#list + 1] = situation(feature, "intro", feature.intro, nil)
	end
	return list
end

-- The moment a due feature would help: explained at once, pointed at if the player hesitates.
function Features.Moment(cloud: any, session: any, props: { [string]: boolean }): Types.CoachSituation?
	local held = session.Hands[1]
	local oven2 = find("oven2")
	if oven2 and held and held.Kind == "Dough" and Features.Due(cloud, oven2) then
		local recipe = Recipes:Get(held.Id)
		local first = session.Stations[Buildings.GetId("Oven", 1)]
		if recipe and recipe.station == "Oven" and first and first.State ~= "Idle" then
			for id, station in session.Stations do
				if station.Kind == "Oven" and station.State == "Idle" and props[id] and Buildings.GetIndex(id) >= 2 then
					return situation(
						oven2,
						id,
						"First oven busy? Use your second oven",
						State.Goal("load_dough", "Put the dough in your second oven", "", id)
					)
				end
			end
		end
	end
	local freezer = find("freezer")
	if freezer and held and held.Kind == "Dough" and Features.Due(cloud, freezer) then
		local recipe = Recipes:Get(held.Id)
		local id = if recipe and recipe.station == "Freezer" then State.Station(session, "Freezer", "Idle") else nil
		if id then
			return situation(
				freezer,
				id,
				"Frozen mixes go in the freezer",
				State.Goal("load_dough", "Put the mix in the freezer", "", id)
			)
		end
	end
	local window = find("window")
	if
		window
		and held
		and held.Kind == "Dish"
		and Features.Due(cloud, window)
		and not ordered(session, held.Id)
		and not State.EmptyDisplay(session, props)
		and props.window_1
		and not session.Window[1]
	then
		return situation(
			window,
			"place",
			"Display full? Use the kitchen window",
			State.Goal("window_place", "Set the dish on the kitchen window", "", "window_1")
		)
	end
	local coffee = find("coffee")
	local recipe = Recipes:Get("coffee")
	if coffee and recipe and Features.Due(cloud, coffee) and ordered(session, recipe.id) then
		local step = Cooking.Resolve(cloud, session, props, recipe, "None")
		-- Another station's batch can come first in that route; this moment is only the machine.
		local target = step and step.target
		if step and not step.waiting and target and string.match(target.id, "^coffee") then
			return situation(coffee, step.id, "A guest wants coffee from the machine", step)
		end
	end
	return nil
end

return Features
