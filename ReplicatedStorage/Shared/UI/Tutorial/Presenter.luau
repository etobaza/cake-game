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
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local Navigation = require(ReplicatedStorage.Shared.Tutorial.Navigation)
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
		GoalKey: string,
		EligibleSince: number,
		AnnouncedAt: number,
		Toast: number?,
		Notify: (string) -> number?,
		Clear: (number) -> (),
	},
	Presenter
))

--[[ Handling ]]
--
function Presenter.new(screen: ScreenGui, notify: (string) -> number?, clear: (number) -> ()): Presenter
	-- Retire the authored card, handbook, help button, and Resume banner on every device.
	screen.Enabled = false

	return setmetatable({
		Screen = screen,
		Focus = Focus.new(screen),
		Collapsed = false,
		Announced = "",
		GoalKey = "",
		EligibleSince = os.clock(),
		AnnouncedAt = 0,
		Notify = notify,
		Clear = clear,
	}, Presenter) :: Presenter
end

function Presenter.Set(self: Presenter, goal: Types.TutorialGoal?, saved: { Collapsed: boolean }): ()
	local key = if goal then goal.id else ""
	if key ~= self.GoalKey then
		self.GoalKey = key
		self.EligibleSince = os.clock()
	end
	self.Goal = goal
	self.Collapsed = saved.Collapsed
	self.Focus:Resolve(goal and goal.target)

	if not goal then
		self.Announced = ""
		self.Focus:Hide()
	end
end

-- A world task's toast must not sit over an unrelated window; announce it again after closing.
local function hideToast(self: Presenter): ()
	if self.Toast then
		self.Clear(self.Toast)
		self.Toast = nil
		self.Announced = ""
	end
end

function Presenter.Draw(self: Presenter, _deltaTime: number, page: string): ()
	local goal = self.Goal
	if page ~= "None" and (not goal or self.Announced ~= goal.id or not Navigation.Matches(goal, page)) then
		hideToast(self)
	end
	local character = Players.LocalPlayer.Character
	if not goal or self.Collapsed or not character or not character.PrimaryPart then
		self.Focus:Hide()
		self.EligibleSince = os.clock()
		return
	end

	if GuiService.MenuIsOpen or not Navigation.Matches(goal, page) then
		self.Focus:Hide()
		self.EligibleSince = os.clock()
		return
	end

	-- A pressing finger promises an action. Cooking/eating need no repeated clicks.
	if goal.waiting then
		self.Focus:Hide()
	else
		self.Focus:Update()
	end

	-- A busy status toast has priority; retry the current goal instead of replacing feedback.
	local now = os.clock()
	local ready = now - self.EligibleSince >= Config.GoalSettleSeconds
	-- Optional lessons are announced once; only the introduction and urgent ovens repeat.
	local repeats = not goal.waiting and (goal.topic == nil or goal.urgent == true)
	local reminder = repeats and now - self.AnnouncedAt >= Config.ReminderSeconds
	local target = self.Focus.Target
	local message = if target and target.message then target.message else goal.title
	if ready and (self.Announced ~= goal.id or reminder) then
		local token = self.Notify(message)
		if token then
			self.Toast = token
			self.Announced = goal.id
			self.AnnouncedAt = now
		end
	end
end

function Presenter.Destroy(self: Presenter): ()
	hideToast(self)
	self.Screen.Enabled = false
	self.Focus:Destroy()
end

return Presenter
