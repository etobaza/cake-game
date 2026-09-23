--!strict
-- Tutorial presentation is a target hint plus a brief message in the existing status toast.

--[[ Services ]]
--
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]
--
local Focus = require(script.Parent.Focus)
local Types = require(ReplicatedStorage.Shared.GameTypes)

--[[ Tables ]]
--
local Presenter = {}
Presenter.__index = Presenter

export type Presenter = typeof(setmetatable(
	{} :: {
		Screen: ScreenGui,
		Focus: Focus.Focus,
		Goal: Types.TutorialGoal?,
		Collapsed: boolean,
		Announced: string,
		Notify: (string) -> boolean,
	},
	Presenter
))

--[[ Private Functions ]]
--
local function matchesPage(goal: Types.TutorialGoal, page: string): boolean
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

--[[ Handling ]]
--
function Presenter.new(screen: ScreenGui, notify: (string) -> boolean): Presenter
	-- Retire the authored card, handbook, help button, and Resume banner on every device.
	screen.Enabled = false

	return setmetatable({
		Screen = screen,
		Focus = Focus.new(screen),
		Collapsed = false,
		Announced = "",
		Notify = notify,
	}, Presenter) :: Presenter
end

function Presenter.Set(self: Presenter, goal: Types.TutorialGoal?, saved: { Collapsed: boolean }): ()
	self.Goal = goal
	self.Collapsed = saved.Collapsed
	self.Focus:Resolve(goal and goal.target)

	if not goal then
		self.Announced = ""
		self.Focus:Hide()
	end
end

function Presenter.Draw(self: Presenter, _deltaTime: number, page: string): ()
	local goal = self.Goal
	local character = Players.LocalPlayer.Character
	if not goal or self.Collapsed or not character or not character.PrimaryPart then
		self.Focus:Hide()
		return
	end

	if GuiService.MenuIsOpen or not matchesPage(goal, page) then
		self.Focus:Hide()
		return
	end

	self.Focus:Update()

	-- A busy status toast has priority; retry the current goal instead of replacing feedback.
	if self.Announced ~= goal.id and self.Notify(goal.title) then
		self.Announced = goal.id
	end
end

function Presenter.Destroy(self: Presenter): ()
	self.Screen.Enabled = false
	self.Focus:Destroy()
end

return Presenter
