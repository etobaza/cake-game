--!strict
-- An unrelated page temporarily redirects guidance without changing tutorial progress.

local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)

local Navigation = {}

function Navigation.Matches(goal: Types.TutorialGoal, page: string): boolean
	if page == "None" then
		return true
	end
	local target = goal.target
	if not target then
		return false
	end
	if target.kind == "Recipe" then
		return page == "RecipeToCook"
	end
	if target.kind == "Gui" and target.id:match("^BakeryMenu%.") then
		return page == "Inventory" or page == "Report" or page == "Upgrades"
	end
	return target.kind == "Gui" and target.id:match("^[^.]+") == page
end

function Navigation.Resolve(goal: Types.TutorialGoal?, page: string, canClose: boolean): Types.TutorialGoal?
	if not goal or not canClose or Navigation.Matches(goal, page) then
		return goal
	end
	local recovery = State.Close(
		"close_page_" .. page,
		"Close this window to continue",
		"Use the back arrow. Your current tutorial task will resume after closing this window.",
		page
	)
	recovery.recovery = true
	recovery.urgent = goal.urgent
	return recovery
end

return Navigation
