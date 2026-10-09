--!strict
-- Client facade: one Janitor owns the authored tutorial, data/page observers and the shared frame callback.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Coach = require(ReplicatedStorage.Shared.Tutorial.Coach)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local DataClient = require(script.Parent.DataHandlerClient)
local Flux = require(ReplicatedStorage.Packages.flux)
local GuestHighlight = require(ReplicatedStorage.Shared.UI.Tutorial.GuestHighlight)
local HintRoute = require(ReplicatedStorage.Shared.UI.HintRoute)
local Interact = require(script.Parent.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Lessons = require(ReplicatedStorage.Shared.Tutorial.Lessons)
local OrderHandler = require(script.Parent.OrderHandler)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Presenter = require(ReplicatedStorage.Shared.UI.Tutorial.Presenter)
local Recipes = require(ReplicatedStorage.Shared.Configs.Registries.Recipes)
local Scenario = require(ReplicatedStorage.Shared.Tutorial.Scenario)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local TopbarHandler = require(script.Parent.TopbarHandler)
local HudReveal = require(ReplicatedStorage.Shared.UI.Stores.HudReveal)
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)
local Types = require(ReplicatedStorage.Shared.GameTypes)
local UIHandler = require(script.Parent.UIHandler)

--[[ Constants ]]--
-- The HUD clock's tutorial target.
local CLOCK_TARGET = "UI.HUD.Time"

--[[ Tables ]]--
local TutorialHandler = {
	-- Resolve authored targets after the data, screen and world-prompt owners are ready.
	dependencies = { "DataClient", "UIHandler", "InteractHandler", "PromptHandler", "OrderHandler", "TopbarHandler" },
	priority = 70,
}

--[[ Private Functions ]]--
local function incomingGuest(cloud: any, session: any): string?
	if not TutorialPolicy.IsActive(cloud) or cloud.Tutorial.Collapsed or not session.Tutorial.Protected then
		return nil
	end

	local guestId = session.Tutorial.GuestId
	local customer = session.Customers[guestId]
	if not customer or not customer.TutorialProtected then
		return nil
	end

	return if customer.State == "Arriving" or customer.State == "Queued" then guestId else nil
end

-- One short line per stage (or optional lesson), so the bubble does not change with every small
-- step; the pointer and the item tile carry the step itself. Recovery and urgent steps, and steps
-- outside any stage, keep their own title.
local function stageLine(cloud: any, session: any, goal: Types.TutorialGoal): string?
	if goal.recovery or goal.urgent then
		return nil
	end
	local lines = Config.Dialog.Lines
	-- The evening plan is its own lesson, even during the introduction.
	if TutorialPolicy.IsActive(cloud) and session.Day.Phase ~= "Summary" then
		local template = lines.Stages[session.Tutorial.Stage]
		if not template then
			return nil
		end
		local recipe = Recipes:Get(TutorialPolicy.Recipe(session) or "")
		return string.format(template, if recipe then recipe.name else "bread")
	end
	return if goal.topic then lines.Topics[goal.topic] else nil
end

-- What the HUD shows while the introduction runs: each element appears when the player first
-- needs it. Side buttons other than HudDuringIntro, the level bar and the topbar row
-- wait for the end; the balance arrives with the Serve stage, just before the first sale; the
-- clock arrives when the player is asked to open (and stays once the bakery has opened).
local function hudShown(cloud: any, session: any, goal: Types.TutorialGoal?): { [string]: boolean }
	local active = TutorialPolicy.IsActive(cloud)
	local stage = session.Tutorial.Stage
	local target = goal and goal.target
	local askedToOpen = target ~= nil and target.kind == "Gui" and target.id == CLOCK_TARGET
	return {
		Side = not active,
		Quests = not active,
		Topbar = not active,
		Currency = not active or stage == "Serve" or stage == "Clean",
		Time = not active or session.Day.Phase ~= "Prep" or askedToOpen,
	}
end

local function sideButtons(): { GuiObject }
	local found, side = pcall(function(): Instance
		return UIHandler:GetHud("SideBtns")
	end)
	local buttons = {}
	if not found then
		return buttons
	end
	for _, button in side:GetChildren() do
		if button:IsA("GuiObject") and not table.find(Config.HudDuringIntro, button.Name) then
			table.insert(buttons, button)
		end
	end
	return buttons
end

-- Groups slide in from their own edge through HydrateHud's Ripple springs (HudReveal). New side
-- buttons cannot slide inside their list on their own, so the column rides out, gains them and
-- rides back in.
local function applyHud(self: any, cloud: any, session: any, goal: Types.TutorialGoal?): ()
	local wanted = hudShown(cloud, session, goal)
	local shown = self.HudShown
	local first = shown == nil
	local current: { [string]: boolean } = shown or {}
	self.HudShown = current

	for _, name in { "Currency", "Time", "Quests" } do
		if current[name] ~= wanted[name] then
			current[name] = wanted[name]
			HudReveal.Set(name, wanted[name])
		end
	end
	if current.Side ~= wanted.Side then
		current.Side = wanted.Side
		local visible = wanted.Side
		if first or not visible then
			for _, button in sideButtons() do
				button.Visible = visible
			end
		else
			HudReveal.Set("SideBtns", false)
			task.delay(Config.HudSideSwapSeconds, function(): ()
				for _, button in sideButtons() do
					button.Visible = true
				end
				HudReveal.Set("SideBtns", true)
			end)
		end
	end
	if current.Topbar ~= wanted.Topbar then
		current.Topbar = wanted.Topbar
		TopbarHandler:SetVisible(wanted.Topbar)
	end
	if first then
		HudReveal.Ready()
	end
end

local function playerRoom(): string?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then HintRoute.Room(root.Position) else nil
end

local function bindViewport(self: any): ()
	self.Janitor:Remove("Viewport")
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self.Janitor:Add(
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function(): ()
			self.View:Draw(0, self.Page)
		end),
		"Disconnect",
		"Viewport"
	)
end

--[[ Handling ]]--
function TutorialHandler.OnStart(self: TutorialHandler): ()
	self.Janitor = Janitor.new()
	self.Page = Pages.Current:peek()
	self.Elapsed = 0
	if not Config.Enabled then
		local screen = UIHandler:GetPanel("Tutorial")
		if screen then
			screen.Enabled = false
		end
		return
	end
	DataClient:WaitForData()
	local screen = UIHandler:GetPanel("Tutorial")
	if not screen then
		print("[TutorialHandler] StarterGui.Tutorial must be authored and saved")
		return
	end
	self.View = Presenter.new(screen, function(text: string): number?
		if UIHandler.StatusVisible:peek() then
			return nil
		end

		return UIHandler:Toast(text)
	end, function(token: number): ()
		UIHandler:ClearToast(token)
	end, function(goalId: string): ()
		-- The bubble's button on a read-only step; the order card is its only one today.
		if goalId == "order_card" then
			local session = DataClient:GetData({}, "Session")
			self.OrderSeen = session and session.Tutorial and session.Tutorial.GuestId
			self:Refresh()
		end
	end)
	self.Janitor:Add(self.View, "Destroy")
	self.Coach = Coach.new()
	self.GuestHighlight = GuestHighlight.new(Players.LocalPlayer.UserId)
	self.Janitor:Add(self.GuestHighlight, "Destroy")
	self.Janitor:Add(
		DataClient:SubscribeToAll(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	-- Repeated misunderstandings raise the coaching level; the refusal toast itself stays UIHandler's.
	self.Janitor:Add(
		Bus.Progress.ActionFailed.OnClientEvent:Connect(function(reason: string): ()
			self.Coach:Failed(reason, os.clock())
			self:Refresh()
		end),
		"Disconnect"
	)
	-- Tapping the first order card ends its preview step.
	self.Janitor:Add(
		OrderHandler.Tapped:Connect(function(customerId: string): ()
			self.OrderSeen = customerId
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.LocalPlayer.CharacterAdded:Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.LocalPlayer.CharacterRemoving:Connect(function(): ()
			self.View.Focus:Hide()
		end),
		"Disconnect"
	)
	local function bindCamera(): ()
		bindViewport(self)
	end
	self.Janitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera), "Disconnect")
	bindCamera()
	local scope = Scope.Run(function(): ()
		Flux(function(): ()
			self.Page = Pages.Current()
			self:Refresh()
		end, true)
	end)
	self.Janitor:Add(scope, "Destroy")
	self.Janitor:Add(
		screen.Destroying:Connect(function(): ()
			self:Destroy()
		end),
		"Disconnect"
	)
	self:Refresh()
end

function TutorialHandler.Refresh(self: TutorialHandler): ()
	if not self.View then
		return
	end
	local cloud = DataClient:GetData({}, "Cloud")
	local session = DataClient:GetData({}, "Session")
	if not cloud or not session or not cloud.Tutorial or not session.Tutorial then
		self.GuestHighlight:Clear()
		return
	end
	local guestId = incomingGuest(cloud, session)
	self.GuestHighlight:Update(guestId)
	local props = Interact:GetOwnedIds()
	local now = workspace:GetServerTimeNow()
	local room = playerRoom()
	-- Walking garden produce indoors after the cart was pointed out means the player prefers their
	-- hands: retire the lesson instead of asking again at every harvest.
	if self.CartPrompted and not self.CartDismissed and Lessons.CarriedPastCart(cloud, session, props, room) then
		self.CartDismissed = true
		Bus.Tutorial.Control:Fire("Dismiss", "Cart")
	end
	local goal = Scenario.Resolve(cloud, session, props, self.Page, now, {
		canClose = Pages.CanOpen(Pages.Names.None),
		orderSeen = self.OrderSeen,
		room = room,
		gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad,
	})
	if goal and goal.id == "cart_load" then
		self.CartPrompted = true
	end
	-- After the introduction, coaching fills the gaps the optional lessons leave.
	local coaching = false
	if goal or TutorialPolicy.IsActive(cloud) or cloud.Tutorial.Collapsed then
		self.Coach:Reset()
	else
		goal = self.Coach:Update(cloud, session, props, self.Page, now, os.clock())
		coaching = goal ~= nil
	end

	local completedAt = session.Tutorial.CompletedAt
	if completedAt > 0 and now - completedAt < Config.SuccessSeconds then
		goal = {
			id = "completed",
			title = "Your bakery is {ready}!",
			hint = "You cooked, served and cleaned your first table. Enjoy your shift!",
			waiting = true,
		}
		coaching = false
	end
	-- The introduction counts its four stages on the bubble.
	local stage = if TutorialPolicy.IsActive(cloud) then Config.Stages[session.Tutorial.Stage] else nil
	local progress = if stage then `{stage}/{Config.Stages.Clean}` else nil
	local line = if goal and not coaching then stageLine(cloud, session, goal) else nil
	-- Other guides stay quiet while the tutorial is showing the player what to do.
	self.Guiding = goal ~= nil and not cloud.Tutorial.Collapsed
	self.TargetId = if goal and goal.target and goal.target.kind == "World" then goal.target.id else nil
	applyHud(self, cloud, session, goal)
	self.View:Set(goal, cloud.Tutorial, coaching, progress, line)
	local needsFrame = goal ~= nil or guestId ~= nil or self.Coach:IsPending()
	if needsFrame and not self.Janitor:Get("Frame") then
		self.Janitor:Add(
			RunService.RenderStepped:Connect(function(deltaTime: number): ()
				self.Elapsed += deltaTime
				if self.Elapsed >= Config.RefreshInterval then
					self.Elapsed = 0
					self:Refresh()
				end
				self.View:Draw(deltaTime, self.Page)
			end),
			"Disconnect",
			"Frame"
		)
	elseif not needsFrame then
		self.Janitor:Remove("Frame")
		self.View:Draw(0, self.Page)
	end
end

function TutorialHandler.Destroy(self: TutorialHandler): ()
	self.Janitor:Destroy()
	self.View = nil
	self.Guiding = false
	self.TargetId = nil
end

export type TutorialHandler = typeof(TutorialHandler) & {
	Janitor: any,
	View: any,
	GuestHighlight: GuestHighlight.GuestHighlight,
	Coach: Coach.Coach,
	Page: string,
	Elapsed: number,
	Guiding: boolean?,
	-- The world target the shown goal points at, if any.
	TargetId: string?,
	-- Which gated HUD parts are showing; nil before the first check.
	HudShown: { [string]: boolean }?,
	-- The guest whose order card the player tapped.
	OrderSeen: string?,
	-- The cart lesson's load prompt was shown, and its dismissal was sent.
	CartPrompted: boolean?,
	CartDismissed: boolean?,
}

return TutorialHandler :: TutorialHandler
