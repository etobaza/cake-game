--!strict
-- Deterministic reads over replicated kitchen data. These functions never grant progress.

--[[ Modules ]]--
local Buildings = require(script.Parent.Parent.Configs.Buildings)
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

function State.FreeHands(session: any, props: { [string]: boolean }, reason: string): Types.TutorialGoal?
	local held = session.Hands[1]
	if not held then
		return nil
	end
	local function recovery(goal: Types.TutorialGoal): Types.TutorialGoal
		goal.recovery = true
		return goal
	end
	if held.Kind == "Tool" then
		return recovery(
			State.Goal("return_tool", "Return the " .. string.lower(Buildings.ToolLabel(held.Id)), reason, held.Id)
		)
	end
	if held.Kind == "Dish" then
		local display = State.EmptyDisplay(session, props)
		if display then
			return recovery(State.Goal("store_dish", "Set this dish on the display", reason, display))
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
	return recovery(
		State.Goal(
			"discard_" .. held.Id,
			if held.Kind == "Burnt" then "Throw away the burnt food" else "Free your hand at the trash",
			reason,
			"trash"
		)
	)
end

function State.SeatGoal(id: string, title: string, hint: string, tableId: string, seat: number): Types.TutorialGoal
	local goal = State.Goal(id, title, hint, tableId)
	if goal.target then
		goal.target.seat = seat
	end
	return goal
end

return State
