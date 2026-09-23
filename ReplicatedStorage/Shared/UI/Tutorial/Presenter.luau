--!strict
-- Drives the authored screen. All focus, motion, preview and input resources belong to this lifetime.

--[[ Services ]]--
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Animate = require(script.Parent.Parent.Animate)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local Focus = require(script.Parent.Focus)
local Geometry = require(script.Parent.Geometry)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Layout = require(script.Parent.Layout)
local Press = require(script.Parent.Parent.Press)
local Preview = require(script.Parent.Preview)
local Types = require(ReplicatedStorage.Shared.GameTypes)

--[[ Types ]]--
-- The authored StarterGui.Tutorial children this presenter wires up.
type AuthoredScreen = ScreenGui & {
	Card: CanvasGroup & { Icon: ImageLabel, Skip: GuiButton, Help: GuiButton },
	Help: GuiObject & { Skip: TextButton },
	HelpButton: GuiButton,
	Compact: TextButton,
}

--[[ Constants ]]--
-- Let page/HUD reflow finish before pinning a dock; brief camera crossings must not move it.
local DOCK_SETTLE_TIME = 0.35
local OVERLAP_DELAY = 0.4
local DOCK_MIN_HOLD = 2
local OVERLAP_TOLERANCE = 64

--[[ Tables ]]--
local Presenter = {}
Presenter.__index = Presenter
local StageNames = {
	Cook = "Your first bake",
	Serve = "Your first guest",
	Clean = "A happy customer",
	Completed = "You're ready!",
	Skipped = "Bakery tip",
}

--[[ Private Functions ]]--
local function matchesPage(goal: Types.TutorialGoal?, page: string): boolean
	if page == "None" then
		return true
	end
	local target = goal and goal.target
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

local function inputHint(goal: Types.TutorialGoal, message: string?): string
	if goal.id == "completed" then
		return "Your shift has started"
	end
	if message then
		return message
	end
	if goal.waiting then
		return "Take your time"
	end
	local gui = goal.target and goal.target.kind ~= "World"
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return if gui then "Tap the highlighted control" else "Walk closer · tap the prompt"
	end
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		local key = UserInputService:GetStringForKeyCode(if gui then Enum.KeyCode.ButtonA else Enum.KeyCode.ButtonX)
			:gsub("^Button", "")
		if gui and not GuiService.SelectedObject then
			local menu = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonY):gsub("^Button", "")
			return menu .. ": menu · " .. key .. ": select"
		end
		return if gui then "Select with the stick · " .. key else "Walk closer · " .. key .. " to interact"
	end
	return if gui then "Click the highlighted control" else "Walk closer · E to interact"
end

local function bind(self: any, button: GuiObject, callback: () -> ()): ()
	if button.Parent and button.Parent:GetAttribute("CloseWrapper") then
		Animate.Press(button, nil, self.Janitor)
		self.Janitor:Add(Press.Bind(button, callback), "Destroy")
		return
	end
	local motion = Animate.Scale(button)
	self.Janitor:Add(motion, "destroy")
	self.Janitor:Add(
		Press.Bind(button, function(): ()
			Animate.Pop(button, 0.94)
			callback()
		end),
		"Destroy"
	)
end

local function dismiss(self: any): ()
	if self.Goal and self.Goal.topic then
		self.Control("Dismiss", self.Goal.topic)
	elseif self.Active then
		self.Control("Skip", "Introduction")
	end
end

local function handbook(self: any): ()
	local template = self.Screen.Help.Topics.TopicTemplate
	for index, topic in Config.Topics do
		local row = template:Clone()
		row.Name = topic.id
		row.LayoutOrder = index
		row.Title.Text = topic.title
		row.Text.Text = topic.text
		row.Visible = true
		row.Active = true
		row.Selectable = true
		row.SelectionOrder = index + 1
		row.Size = UDim2.new(1, -8, 0, 162)
		row.Parent = template.Parent
		self.Janitor:Add(row, "Destroy")
	end
end

local function measureHint(self: any, width: number, textSize: number): ()
	local label = self.Screen.Card.Hint.Content
	local key = label.Text .. ":" .. width .. ":" .. textSize
	if self.MeasureKey == key then
		return
	end
	self.MeasureKey = key
	self.MeasureJanitor:Cleanup()
	local params = Instance.new("GetTextBoundsParams")
	params.Text, params.Font, params.Size, params.Width = label.Text, label.FontFace, textSize, width
	self.MeasureJanitor:Add(params, "Destroy")
	self.MeasureJanitor:Add(
		task.defer(function(): ()
			local ok, bounds = pcall(function(): Vector2
				return TextService:GetTextBoundsAsync(params)
			end)
			if not ok then
				warn(`[TutorialPresenter] Could not measure hint: {bounds}`)
				return
			end
			if self.MeasureKey ~= key then
				return
			end
			self.HintHeight = math.ceil(bounds.Y) + 2
			label.Size = UDim2.new(1, -4, 0, self.HintHeight)
		end),
		true
	)
end

-- A dock survives target motion. Only a sustained overlap with an actionable control
-- can dislodge it, and the old dock is not preferred again when that control disappears.
local function place(
	self: any,
	key: string,
	viewport: Vector2,
	size: Vector2,
	protected: Geometry.Rect?,
	deltaTime: number
): ()
	if self.PlacementKey ~= key then
		self.PlacementKey = key
		self.PlacementAge, self.PlacementDirty, self.OverlapAge = 0, true, 0
	end
	self.PlacementAge += deltaTime
	if self.PlacementDirty and self.PlacementAge < DOCK_SETTLE_TIME then
		return
	end
	local occupied = { min = self.Position, max = self.Position + size }
	local overlap = if protected then Geometry.Area(Geometry.Intersect(occupied, protected)) else 0
	self.OverlapAge = if overlap > OVERLAP_TOLERANCE then self.OverlapAge + deltaTime else 0
	if not self.PlacementDirty and (self.OverlapAge < OVERLAP_DELAY or self.PlacementAge < DOCK_MIN_HOLD) then
		return
	end
	local position =
		Layout.Place(viewport, size, self.Obstacles, protected, if self.PlacementDirty then nil else self.Position)
	if not self.PlacementDirty and protected then
		local remaining = Geometry.Area(Geometry.Intersect({ min = position, max = position + size }, protected))
		if remaining > OVERLAP_TOLERANCE then
			self.OverlapAge = 0
			return
		end
	end
	self.Position = position
	self.PlacementDirty, self.PlacementAge, self.OverlapAge = false, 0, 0
	self.Fade:setPosition(0.9)
	self.Fade:spring(0, { frequency = 7, dampingRatio = 1 })
end

--[[ Handling ]]--
function Presenter.new(
	authored: ScreenGui,
	hud: Frame,
	previewTemplate: ViewportFrame,
	control: (string, string) -> ()
): Presenter
	local screen = authored :: AuthoredScreen
	screen.DisplayOrder = 60
	local self: any = setmetatable({
		Screen = screen,
		Hud = hud,
		Janitor = Janitor.new(),
		Key = "",
		Goal = nil,
		Collapsed = false,
		Active = false,
		Control = control,
	}, Presenter)
	self.MeasureJanitor, self.HintHeight, self.MeasureKey = Janitor.new(), 42, ""
	self.Obstacles = Layout.Collect(hud)
	self.Page = "None"
	self.PlacementKey, self.Position = "", Vector2.zero
	self.PlacementAge, self.PlacementDirty, self.OverlapAge = 0, true, 0
	self.Janitor:Add(self.MeasureJanitor, "Destroy")
	self.Focus = Focus.new(screen)
	self.Janitor:Add(self.Focus, "Destroy")
	self.Preview = Preview.new(screen.Card.Icon, previewTemplate)
	self.Janitor:Add(self.Preview, "Destroy")
	self.Fade = Animate.Track(screen.Card, "GroupTransparency", 0, function(value: number): ()
		screen.Card.GroupTransparency = value
	end)
	self.Janitor:Add(self.Fade, "destroy")
	self.Janitor:Add(Animate.Scale(screen.Card), "destroy")
	self.Janitor:Add(Animate.Scale(screen.Help), "destroy")
	local collapse = screen.Card:FindFirstChild("Collapse", true) :: GuiButton
	local helpClose = screen.Help:FindFirstChild("Close", true) :: GuiButton
	bind(self, collapse, function(): ()
		control("Collapse", "true")
	end)
	bind(self, screen.Card.Skip, function(): ()
		dismiss(self)
	end)
	bind(self, screen.Compact, function(): ()
		control("Collapse", "false")
	end)
	bind(self, screen.HelpButton, function(): ()
		screen:SetAttribute("HelpOpen", not screen.Help.Visible)
	end)
	bind(self, screen.Card.Help, function(): ()
		screen:SetAttribute("HelpOpen", true)
	end)
	bind(self, helpClose, function(): ()
		screen:SetAttribute("HelpOpen", false)
	end)
	bind(self, screen.Help.Skip, function(): ()
		dismiss(self)
		screen:SetAttribute("HelpOpen", false)
	end)
	self.Janitor:Add(
		screen:GetAttributeChangedSignal("HelpOpen"):Connect(function(): ()
			screen.Help.Visible = screen:GetAttribute("HelpOpen") == true
			if screen.Help.Visible then
				Animate.Pop(screen.Help, 0.96)
				if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
					GuiService.SelectedObject = helpClose
				end
			end
			self:Draw(0, self.Page)
		end),
		"Disconnect"
	)
	handbook(self)
	screen.Enabled = true
	self:Draw(0, "None")
	return self
end

function Presenter.Set(self: Presenter, goal: Types.TutorialGoal?, saved: any, context: any): ()
	self.Goal = goal
	self.Collapsed = saved.Collapsed
	self.Active = saved.Status == "Active"
	self.Screen.Help.Skip.Visible = self.Active or (goal ~= nil and goal.topic ~= nil)
	self.Screen.Help.Skip.Text = if goal and goal.topic
		then "Got it · dismiss this tip"
		else "I'll figure it out · skip introduction"
	self.Obstacles = Layout.Collect(self.Hud)
	self.Focus:Resolve(goal and goal.target)
	if not goal then
		self:Draw(0, "None")
		return
	end
	if self.Key ~= goal.id then
		self.Key = goal.id
		self.Screen.Card.Hint.CanvasPosition = Vector2.zero
		self.Fade:setPosition(0.9)
		self.Fade:spring(0, { frequency = 7, dampingRatio = 1 })
		if goal.id == "completed" then
			Animate.Pop(self.Screen.Card, 0.88)
		end
	end
	local card = self.Screen.Card
	card.Done.Visible = goal.id == "completed"
	card.Icon.Visible = goal.id ~= "completed"
	card.Title.Text = goal.title
	card.Stage.Text = if goal.topic then "Bakery tip" else StageNames[context.Stage] or "Bakery tip"
	card.Progress.Text = if self.Active then tostring(Config.Stages[context.Stage] or 1) .. " / 3" else ""
	card.Skip.Text = if goal.topic then "Got it" else "Skip introduction"
	card.Skip.Visible = self.Active or goal.topic ~= nil
	self.Preview:Show(goal)
end

function Presenter.Draw(self: Presenter, deltaTime: number, page: string): ()
	self.Page = page
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local safe = Layout.Safe(viewport)
	local screen = self.Screen
	screen.HelpButton.Position = Geometry.ToScreen(screen, Vector2.new(safe.max.X - 22, safe.min.Y + 22))
	screen.Help.Size = UDim2.fromOffset(math.min(460, safe.max.X - safe.min.X), math.min(510, safe.max.Y - safe.min.Y))
	screen.Help.Position = Geometry.ToScreen(screen, (safe.min + safe.max) / 2)
	local goal = self.Goal
	local character = Players.LocalPlayer.Character
	local small = viewport.Y < 420 or viewport.X < 600
	-- A small viewport changes layout, never silently disables guidance.
	local collapsed = self.Collapsed
	local characterMissing = not character or not character.Parent or not character.PrimaryPart
	local paused = characterMissing or not matchesPage(goal, page)
	local shown = goal ~= nil and not paused and not screen.Help.Visible and not GuiService.MenuIsOpen
	-- Page lessons may highlight a control, but the text card does not belong over a menu.
	-- Keep the saved collapse preference so the same HUD presentation returns on close.
	screen.Card.Visible = shown and page == "None" and not collapsed
	-- Pages already have their own close control in the top-right corner on phones.
	-- Expanded tips own an inline help button; the floating one is for the ordinary HUD.
	screen.HelpButton.Visible = page == "None" and not screen.Card.Visible and not screen.Help.Visible
	local compact = screen.Compact
	compact.Visible = shown and (collapsed or page ~= "None")
	if not goal or not shown then
		self.Focus:Hide()
		return
	end
	compact.Text = if collapsed then "Resume · " .. goal.title else goal.title
	compact.TextSize = if small then 14 else 16
	local compactWidth = math.min(360, safe.max.X - safe.min.X)
	compact.Size = UDim2.fromOffset(compactWidth, 48)
	compact.AnchorPoint = Vector2.zero
	local rect, message = nil, nil
	if not collapsed and not paused then
		rect, message = self.Focus:Update()
	else
		self.Focus:Hide()
	end
	local card = screen.Card
	card.Input.Text = inputHint(goal, message)
	local width = math.min(if small then 280 else 360, safe.max.X - safe.min.X)
	local reservedHeight = if small then 154 else 230
	card.Stage.TextSize = if small then 14 else 16
	card.Stage.Size = UDim2.new(1, -130, 0, 26)
	card.Ribbon.Size = UDim2.new(1, -106, 0, 32)
	card.Icon.Position = UDim2.fromOffset(16, if small then 44 else 52)
	card.Icon.Size = UDim2.fromOffset(if small then 38 else 54, if small then 38 else 54)
	card.Done.Position, card.Done.Size = card.Icon.Position, card.Icon.Size
	card.Title.Position = UDim2.fromOffset(if small then 64 else 82, if small then 42 else 48)
	card.Title.Size = UDim2.new(1, if small then -80 else -98, 0, if small then 42 else 56)
	card.Title.TextSize = if small then 16 else 20
	card.Input.Position = UDim2.fromOffset(16, if small then 86 else 108)
	card.Input.Size = UDim2.new(1, -32, 0, if small then 26 else 30)
	card.Input.TextSize = if small then 12 else 14
	card.Hint.Content.TextSize = if small then 12 else 14
	card.Hint.Content.Text = goal.hint
	measureHint(self, width - 36, card.Hint.Content.TextSize)
	local hintTop = if small then 112 else 142
	local footer = if small then 8 else 46
	local height = if small then 154 else 184
	if not small then
		height = math.clamp(hintTop + self.HintHeight + footer, height, reservedHeight)
	end
	card.Hint.Visible = true
	card.Input.Visible = true
	card.Skip.Visible = not small and (self.Active or goal.topic ~= nil)
	card.Footer.Visible, card.Progress.Visible = not small, not small
	card.Skip.TextSize = 14
	card.Skip.Position = UDim2.new(0, 91, 1, -24)
	card.Size = UDim2.fromOffset(width, height)
	card.Hint.Position = UDim2.fromOffset(16, hintTop)
	card.Hint.Size = UDim2.new(1, -32, 0, math.max(1, height - hintTop - footer))
	local gui = if self.Focus.GoalGui then rect else nil
	local guiGoal = goal.target and goal.target.kind ~= "World"
	local placementKey = `{viewport}:{safe.min}:{safe.max}:{page}:{if guiGoal then goal.id else "World"}`
	local protected = gui or self.Focus.PromptBounds
	place(self, placementKey, viewport, Vector2.new(width, reservedHeight), protected, deltaTime)
	if self.PlacementDirty then
		screen.Card.Visible = false
	end
	card.Position = Geometry.ToScreen(screen, self.Position)
	if compact.Visible then
		local compactPosition = Layout.Place(viewport, Vector2.new(compactWidth, 48), self.Obstacles, protected, nil)
		compact.Position = Geometry.ToScreen(screen, compactPosition)
	end
end

function Presenter.Destroy(self: Presenter): ()
	self.Screen.Card.Visible = false
	self.Screen.Help.Visible = false
	self.Screen.Compact.Visible = false
	self.Janitor:Destroy()
end

export type Presenter = typeof(setmetatable(
	{} :: {
		Screen: any,
		Hud: Frame,
		Janitor: any,
		MeasureJanitor: any,
		MeasureKey: string,
		HintHeight: number,
		Focus: Focus.Focus,
		Preview: Preview.Preview,
		Fade: any,
		Key: string,
		Goal: Types.TutorialGoal?,
		Collapsed: boolean,
		Active: boolean,
		Control: (string, string) -> (),
		Page: string,
		Obstacles: { GuiObject },
		PlacementKey: string,
		Position: Vector2,
		PlacementAge: number,
		PlacementDirty: boolean,
		OverlapAge: number,
	},
	Presenter
))

return Presenter
