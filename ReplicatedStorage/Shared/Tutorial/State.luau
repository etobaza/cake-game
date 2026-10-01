--!strict
-- Deterministic reads over replicated kitchen data. These functions never grant progress.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
local CarryPolicy = require(script.Parent.Parent.CarryPolicy)
local Ingredients = require(script.Parent.Parent.Configs.Registries.Ingredients)
local Recipes = require(script.Parent.Parent.Configs.Registries.Recipes)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Tables ]]--
local State = {}

--[[ Handling ]]--
function State.Goal(id: string, title: string, hint: string, target: string?): Types.TutorialGoal
	local tool = target and Buildings.GetToolId(target)
	return {
		id = id,
		title = title,
		hint = hint,
		target = if target then { kind = "World", id = target } else nil,
		itemId = if target == "fuel" then Buildings.FuelItemId else tool,
		itemKind = if target == "fuel" then "Fuel" elseif tool then "Tool" else nil,
	}
end

function State.Gui(id: string, title: string, hint: string, path: string): Types.TutorialGoal
	local goal = State.Goal(id, title, hint, nil)
	goal.target = { kind = "Gui", id = path }
	return goal
end

function State.Close(id: string, title: string, hint: string, page: string): Types.TutorialGoal
	local goal = State.Goal(id, title, hint, nil)
	goal.target = { kind = "Gui", id = page .. ".Exit", control = "Close" }
	return goal
end

function State.Station(session: any, kind: string, desired: string?): (string?, any?)
	local ids = {}
	for id, station in session.Stations do
		if station.Kind == kind and (not desired or station.State == desired) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local id = ids[1]
	return id, if id then session.Stations[id] else nil
end

function State.EmptyDisplay(session: any, props: { [string]: boolean }): string?
	for index = 1, 8 do
		local id = Buildings.GetId("Display", index)
		if props[id] and not session.Display[index] then
			return id
		end
	end
	return nil
end

-- Returns the goal that frees the hand, and whether the hand is already usable.
-- Dispenser ingredients go back to their source on the next pickup, so they never block.
-- Only burnt food is thrown away by default. `discard` lets the introduction bin other
-- items as a last resort; optional lessons pass false and wait (nil goal, not ready).
function State.FreeHands(
	session: any,
	props: { [string]: boolean },
	reason: string,
	discard: boolean
): (Types.TutorialGoal?, boolean)
	local held = session.Hands[1]
	if not held or CarryPolicy.CanReplace(held) then
		return nil, true
	end
	local function recovery(goal: Types.TutorialGoal): (Types.TutorialGoal?, boolean)
		goal.recovery = true
		return goal, false
	end
	if held.Kind == "Tool" then
		return recovery(
			State.Goal("return_tool", "Return the " .. string.lower(Buildings.ToolLabel(held.Id)), reason, held.Id)
		)
	end
	if held.Kind == "Dish" or held.Kind == "Leftover" then
		local display = State.EmptyDisplay(session, props)
		if display then
			return recovery(State.Goal("store_dish", "Set this dish on the display", reason, display))
		end
	end
	if held.Kind == "Dough" then
		local recipe = Recipes:Get(held.Id)
		local id = recipe and State.Station(session, recipe.station, "Idle")
		if recipe and id then
			return recovery(State.Goal("store_dough", "Put the dough in the " .. string.lower(recipe.station), reason, id))
		end
	end
	if held.Kind == "Fuel" then
		for id, station in session.Stations do
			if not Buildings.Kinds[station.Kind].UsesFuel then
				continue
			end
			return recovery(State.Goal("store_fuel", "Put this log in the oven", reason, id))
		end
	end
	if held.Kind == "Burnt" then
		return recovery(State.Goal("discard_" .. held.Id, "Throw away the burnt food", reason, "trash"))
	end
	if not discard then
		return nil, false
	end
	local entry = if held.Kind == "Ingredient" then Ingredients:Get(held.Id) else Recipes:Get(held.Id)
	local name = if entry then entry.name else "item"
	return recovery(State.Goal("discard_" .. held.Id, "Throw away the " .. string.lower(name), reason, "trash"))
end

function State.SeatGoal(id: string, title: string, hint: string, tableId: string, seat: number): Types.TutorialGoal
	local goal = State.Goal(id, title, hint, tableId)
	if goal.target then
		goal.target.seat = seat
	end
	return goal
end

return State
