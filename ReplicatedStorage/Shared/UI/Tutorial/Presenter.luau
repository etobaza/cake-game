--!strict
-- Tutorial presentation: a target hint plus the guide's speech bubble (Dialog), which stays up for
-- as long as its step is active. Post-introduction coaching keeps the brief status toast.

--[[ Services ]]
--
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]
--
local Dialog = require(script.Parent.Dialog)
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
		Dialog: Dialog.Dialog,
		Goal: Types.TutorialGoal?,
		-- Coaching goals keep the short status toast instead of the bubble.
		Coaching: boolean,
		Progress: string?,
		-- The bubble's line for this step: the stage line during the introduction.
		Line: string?,
		TargetOutline: Highlight?,
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
function Presenter.new(
	screen: ScreenGui,
	notify: (string) -> number?,
	clear: (number) -> (),
	acknowledge: (string) -> ()
): Presenter
	-- Retire the authored card, handbook, help button, and Resume banner on every device.
	screen.Enabled = false

	return setmetatable({
		Screen = screen,
		Focus = Focus.new(screen),
		Dialog = Dialog.new(acknowledge),
		Coaching = false,
		Collapsed = false,
		Announced = "",
		GoalKey = "",
		EligibleSince = os.clock(),
		AnnouncedAt = 0,
		Notify = notify,
		Clear = clear,
	}, Presenter) :: Presenter
end

function Presenter.Set(
	self: Presenter,
	goal: Types.TutorialGoal?,
	saved: { Collapsed: boolean },
	coaching: boolean?,
	progress: string?,
	line: string?
): ()
	local key = if goal then goal.id else ""
	if key ~= self.GoalKey then
		self.GoalKey = key
		self.EligibleSince = os.clock()
	end
	self.Goal = goal
	self.Coaching = coaching == true
	self.Progress = progress
	self.Line = line
	self.Collapsed = saved.Collapsed
	self.Focus:Resolve(goal and goal.target)
	self:Outline(if goal and goal.highlight and self.Focus.Target then self.Focus.Target.model else nil)

	if not goal then
		self.Announced = ""
		self.Focus:Hide()
		self.Dialog:Hide()
	end
end

-- A world target the step asks to find (the tutorial spill) glows like the incoming guest.
function Presenter.Outline(self: Presenter, model: Instance?): ()
	local outline = self.TargetOutline
	if outline and outline.Parent and outline.Adornee == model and model then
		return
	end
	if outline then
		outline:Destroy()
		self.TargetOutline = nil
	end
	if not model then
		return
	end
	local style = Config.GuestHighlight
	local created = Instance.new("Highlight")
	created.Name = "TutorialTargetHighlight"
	created.Adornee = model
	created.DepthMode = style.DepthMode
	created.FillColor = style.Color
	created.FillTransparency = style.FillTransparency
	created.OutlineColor = style.Color
	created.OutlineTransparency = style.OutlineTransparency
	created.Parent = model
	self.TargetOutline = created
end

-- Screen rectangle of the step's own GUI target, in the dialog's inset-ignoring space.
local function targetRect(self: Presenter): Rect?
	local target = self.Focus.Target
	local gui = target and target.gui
	if not gui then
		return nil
	end
	local screen = gui:FindFirstAncestorWhichIsA("LayerCollector")
	local inset = if screen and screen:IsA("ScreenGui") and not screen.IgnoreGuiInset
		then GuiService:GetGuiInset()
		else Vector2.zero
	local min = gui.AbsolutePosition + inset
	return Rect.new(min, min + gui.AbsoluteSize)
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
		self.Dialog:Hide()
		self.EligibleSince = os.clock()
		return
	end

	if GuiService.MenuIsOpen or not Navigation.Matches(goal, page) then
		self.Focus:Hide()
		self.Dialog:Hide()
		self.EligibleSince = os.clock()
		return
	end

	-- A pressing finger promises an action. Cooking/eating need no repeated clicks. The player
	-- first gets a moment to find the target alone: the finger follows after PointDelay and the
	-- dimming spotlight after FocusDelay (urgent steps point at once).
	local waited = os.clock() - self.EligibleSince
	local pointAfter = if goal.urgent then 0 else Config.PointDelay
	if goal.waiting or waited < pointAfter then
		self.Focus:Hide()
	else
		self.Focus:Update(goal.urgent == true or waited >= Config.FocusDelay)
	end

	local target = self.Focus.Target
	local message = if target and target.message then target.message else goal.title
	if not self.Coaching then
		-- The bubble owns the step: it stays up, so it never waits behind other toasts.
		hideToast(self)
		local shown = table.clone(goal)
		shown.title = self.Line or goal.title
		-- A target that is out of reach (a scrolled recipe, a far mixer) says how to reach it.
		if target and target.message then
			shown.title = target.message
		end
		self.Dialog:SetAvoid(targetRect(self))
		self.Dialog:Show(shown, self.Progress)
		return
	end
	self.Dialog:Hide()

	-- A busy status toast has priority; retry the current goal instead of replacing feedback.
	local now = os.clock()
	local ready = now - self.EligibleSince >= Config.GoalSettleSeconds
	-- Optional lessons are announced once; only the introduction and urgent ovens repeat.
	local repeats = not goal.waiting and (goal.topic == nil or goal.urgent == true)
	local reminder = repeats and now - self.AnnouncedAt >= Config.ReminderSeconds
	message = string.gsub(message, "[{}]", "")
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
	self:Outline(nil)
	self.Screen.Enabled = false
	self.Focus:Destroy()
	self.Dialog:Destroy()
end

return Presenter
