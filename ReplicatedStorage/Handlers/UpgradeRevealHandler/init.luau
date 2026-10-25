--!strict
-- Accepted purchases become short, cancellable world reveals. No snapshot or admin grant celebrates.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage.Shared
local Appearance = require(script.Appearance)
local Bus = require(Shared.Bus)
local Camera = require(script.Camera)
local Card = require(script.Card)
local Config = require(Shared.Configs.UpgradeReveal)
local DataClient = require(script.Parent.DataHandlerClient)
local Ease = require(Shared.UI.Ease)
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(Shared.UI.Stores.Pages)
local Scope = require(Shared.UI.Scope)
local SoundPlayer = require(Shared.SoundPlayer)
local Target = require(script.Target)
local UIHandler = require(script.Parent.UIHandler)
local Upgrades = require(Shared.Configs.Registries.Upgrades)

local INPUT_ACTION = "CakeUpgradeRevealInput"
local SKIP_ACTION = "CakeUpgradeRevealSkip"
local PRIORITY = Enum.ContextActionPriority.High.Value + 100
type Notice = { Id: string, Level: number, ExpiresAt: number, Appearance: Appearance.Appearance? }
type Armed = {
	Id: string,
	Level: number,
	ExpiresAt: number,
	NextCapture: number,
	Appearance: Appearance.Appearance,
}
type Run = {
	Notice: Notice,
	Phase: string,
	Age: number,
	NextCapture: number,
	Page: string,
	DayPhase: string,
	Character: Model?,
	Token: number?,
	Camera: Camera.Camera?,
	Target: Target.Target?,
	Lifetime: any,
	Mouse: Enum.MouseBehavior,
	MouseIcon: boolean,
	Selection: GuiObject?,
}

local UpgradeRevealHandler = { dependencies = { "DataClient", "UIHandler" }, priority = 65 }

local function key(id: string, level: number): string
	return `{id}:{level}`
end

local function release(notice: Notice): ()
	if notice.Appearance then
		notice.Appearance:Destroy()
		notice.Appearance = nil
	end
end

function UpgradeRevealHandler.OnInit(self: UpgradeRevealHandler): ()
	self.Janitor = Janitor.new()
	self.Queue = {}
	self.Armed = {}
	self.Seen = {}
end

function UpgradeRevealHandler.OnStart(self: UpgradeRevealHandler): ()
	self.Card = Card.new(function(): ()
		self:Skip()
	end)
	self.Janitor:Add(self.Card, "Destroy")
	self.Janitor:Add(
		Bus.Progress.UpgradeBought.OnClientEvent:Connect(function(id: string, level: number, _cost: number): ()
			self:Purchased(id, level)
		end),
		"Disconnect"
	)
	-- A failed intent releases its pre-purchase mask; it never starts a reveal.
	self.Janitor:Add(
		Bus.Progress.ActionFailed.OnClientEvent:Connect(function(): ()
			self:ClearArmed()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.LocalPlayer.CharacterRemoving:Connect(function(): ()
			self:Cancel()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function(): ()
			self:Cancel()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		GuiService.MenuOpened:Connect(function(): ()
			self:Cancel()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		DataClient:SubscribeToAll(function(): ()
			local run = self.Current
			if run and DataClient:GetData({ "Day", "Phase" }, "Session") ~= run.DayPhase then
				self:Cancel()
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Scope.Run(function(): ()
			Flux(function(): ()
				local page = Pages.Current()
				local run = self.Current
				if run and page ~= run.Page then
					self:Cancel()
				end
			end, true)
		end),
		"Destroy"
	)
	-- Losing the Upgrades panel only drops what it started (masks armed by its Purchase press and a
	-- reveal over it); world reveals for later purchases keep working.
	local panel = UIHandler:GetPanel("Upgrades")
	if panel then
		self.Janitor:Add(
			panel.Destroying:Connect(function(): ()
				self:Cancel()
			end),
			"Disconnect"
		)
	end
end

function UpgradeRevealHandler.EnsureFrame(self: UpgradeRevealHandler): ()
	if self.Janitor:Get("Frame") then
		return
	end
	self.Janitor:Add(
		RunService.RenderStepped:Connect(function(deltaTime: number): ()
			local ok, problem = pcall(function(): boolean
				self:Step(deltaTime)
				return true
			end)
			if not ok then
				self:Cancel()
				print(`[UpgradeRevealHandler] Reveal cancelled: {problem}`)
			end
		end),
		"Disconnect",
		"Frame"
	)
end

-- Before the request, mask only currently hidden geometry. Rejections/timeouts restore it.
function UpgradeRevealHandler.Prepare(self: UpgradeRevealHandler, id: string, level: number): ()
	if self.Destroyed then
		return
	end
	local spec = Config.Targets[id]
	local bakery = Target.Bakery()
	if self.Current or not bakery or not spec or not spec.Fade then
		return
	end
	self:ClearArmed()
	local appearance = Appearance.new()
	appearance:Capture(Target.Roots(bakery, id, level), true)
	local now = os.clock()
	self.Armed[key(id, level)] = {
		Id = id,
		Level = level,
		ExpiresAt = now + Config.ArmLifetime,
		NextCapture = now + Config.CaptureInterval,
		Appearance = appearance,
	}
	self:EnsureFrame()
end

function UpgradeRevealHandler.ClearArmed(self: UpgradeRevealHandler): ()
	for _, armed in self.Armed do
		armed.Appearance:Destroy()
	end
	table.clear(self.Armed)
end

function UpgradeRevealHandler.Purchased(self: UpgradeRevealHandler, id: string, level: number): ()
	local entry = Upgrades:Get(id)
	if
		self.Destroyed
		or not entry
		or level < 1
		or level > entry.maxLevel
		or level % 1 ~= 0
		or level <= (self.Seen[id] or 0)
	then
		return
	end
	self.Seen[id] = level
	local armed = self.Armed[key(id, level)]
	self.Armed[key(id, level)] = nil
	local notice: Notice = {
		Id = id,
		Level = level,
		ExpiresAt = os.clock() + Config.QueueLifetime,
		Appearance = if armed then armed.Appearance else nil,
	}
	if GuiService.MenuIsOpen then
		release(notice)
		return
	end
	if #self.Queue >= Config.MaxQueued then
		release(assert(table.remove(self.Queue, 1)))
	end
	table.insert(self.Queue, notice)
	self:EnsureFrame()
	self:Next()
end

function UpgradeRevealHandler.Next(self: UpgradeRevealHandler): ()
	if self.Current or #self.Queue == 0 then
		return
	end
	local notice = assert(table.remove(self.Queue, 1))
	if notice.ExpiresAt < os.clock() then
		release(notice)
		self:Next()
		return
	end
	local run: Run = {
		Notice = notice,
		Phase = "Waiting",
		Age = 0,
		NextCapture = 0,
		Page = Pages.Current:peek(),
		DayPhase = DataClient:GetData({ "Day", "Phase" }, "Session") or "Prep",
		Character = Players.LocalPlayer.Character,
		Lifetime = Janitor.new(),
		Mouse = UserInputService.MouseBehavior,
		MouseIcon = UserInputService.MouseIconEnabled,
		Selection = GuiService.SelectedObject,
	}
	self.Current = run
	run.Token = Pages.BeginPresentation()
	if not run.Token then
		self:Finish()
		return
	end
	self.Card:Show(notice.Id, notice.Level)
	-- The UI shield consumes touch/clicks; this keyed action blocks movement and interaction only.
	local shield = Instance.new("TextButton")
	shield.Name = "InputShield"
	shield.Text = ""
	shield.BackgroundTransparency = 1
	shield.Size = UDim2.fromScale(1, 1)
	shield.Selectable = false
	shield.Active = true
	shield.ZIndex = 1
	shield.Parent = self.Card.Cover
	run.Lifetime:Add(shield, "Destroy")
	ContextActionService:BindActionAtPriority(
		INPUT_ACTION,
		function(): Enum.ContextActionResult
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump,
		Enum.KeyCode.E,
		Enum.KeyCode.R,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:BindActionAtPriority(
		SKIP_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				self:Skip()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY + 1,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonB
	)
	run.Lifetime:Add(function(): ()
		ContextActionService:UnbindAction(INPUT_ACTION)
		ContextActionService:UnbindAction(SKIP_ACTION)
	end)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = self.Card.Skip
	end
	local humanoid = run.Character and run.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		run.Lifetime:Add(
			humanoid.Died:Connect(function(): ()
				self:Cancel()
			end),
			"Disconnect"
		)
	end
	run.Lifetime:Add(SoundPlayer.Play(Config.Sound), "Destroy")
end

function UpgradeRevealHandler.Reveal(self: UpgradeRevealHandler, target: Target.Target?): ()
	local run = self.Current
	if not run then
		return
	end
	run.Target = target
	run.Phase = "Showing"
	run.Age = 0
	local spec = Config.Targets[run.Notice.Id]
	if not target then
		release(run.Notice)
		return
	end
	if spec and spec.Fade then
		local appearance = run.Notice.Appearance or Appearance.new()
		run.Notice.Appearance = appearance
		appearance:Capture(target.Roots, false)
		run.NextCapture = os.clock() + Config.CaptureInterval
	end
	run.Camera = Camera.new(target)
	local part = Instance.new("Part")
	part.Name = "UpgradeRevealGlints"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = target.Frame
	part.Parent = target.Bakery
	run.Lifetime:Add(part, "Destroy")
	local template: Instance? = ReplicatedStorage.Assets.VFX
	for _, name in Config.VFX.Template do
		template = template and template:FindFirstChild(name, true)
	end
	if template and template:IsA("ParticleEmitter") then
		local glints = template:Clone()
		glints.Enabled = false
		glints.Color = ColorSequence.new(Config.Card.Accent, Config.Card.Cream)
		glints.Size = NumberSequence.new(Config.VFX.Size)
		glints.Speed = Config.VFX.Speed
		glints.Parent = part
		glints:Emit(Config.VFX.Count)
	end
	run.Lifetime:Add(SoundPlayer.Play(Config.Flourish, nil, Config.FlourishPitch), "Destroy")
end

function UpgradeRevealHandler.BeginReturn(self: UpgradeRevealHandler): ()
	local run = self.Current
	if not run or run.Phase == "Returning" then
		return
	end
	release(run.Notice)
	run.Phase = "Returning"
	run.Age = 0
	if run.Camera then
		run.Camera:BeginReturn()
	end
end

function UpgradeRevealHandler.Step(self: UpgradeRevealHandler, deltaTime: number): ()
	local now = os.clock()
	for id, armed in self.Armed do
		if now >= armed.ExpiresAt then
			armed.Appearance:Destroy()
			self.Armed[id] = nil
		elseif now >= armed.NextCapture then
			-- Catch hidden parts that replicated after the press, without a per-frame descendant walk.
			armed.NextCapture = now + Config.CaptureInterval
			local bakery = Target.Bakery()
			if bakery then
				armed.Appearance:Capture(Target.Roots(bakery, armed.Id, armed.Level), true)
			end
		end
	end
	local run = self.Current
	if not run then
		self:Next()
		if not self.Current and next(self.Armed) == nil then
			self.Janitor:Remove("Frame")
		end
		return
	end
	if
		run.Character ~= Players.LocalPlayer.Character
		or (run.Camera and not run.Camera:Owned())
		or (run.Target and not run.Target.Bakery.Parent)
	then
		self:Cancel()
		return
	end
	run.Age += deltaTime
	local veil = 0
	local duration = Config.ApproachSeconds + Config.HoldSeconds
	if run.Phase == "Waiting" then
		local target = Target.Find(run.Notice.Id, run.Notice.Level)
		if run.Age >= Config.ReplicationSettle and (target or run.Age >= Config.ReplicationWait) then
			self:Reveal(target)
		end
	elseif run.Phase == "Showing" then
		local appearance = run.Notice.Appearance
		if appearance and run.Target then
			if now >= run.NextCapture then
				run.NextCapture = now + Config.CaptureInterval
				appearance:Capture(run.Target.Roots, false)
			end
			local fadeAge = run.Age - Config.ApproachSeconds * Config.FadeStartShare
			appearance:Set(Ease.OutCubic(math.max(0, fadeAge) / Config.FadeSeconds))
		end
		if run.Camera then
			if run.Age < Config.ApproachSeconds then
				veil = run.Camera:Approach(Ease.OutCubic(run.Age / Config.ApproachSeconds))
			else
				run.Camera:Orbit(Ease.OutCubic((run.Age - Config.ApproachSeconds) / Config.HoldSeconds))
			end
		end
		if run.Age >= duration then
			self:BeginReturn()
		end
	else
		if run.Camera then
			veil = run.Camera:Return(Ease.OutCubic(run.Age / Config.ReturnSeconds))
		end
		if run.Age >= Config.ReturnSeconds then
			self:Finish()
			return
		end
	end
	self.Card:Step(deltaTime, run.Age, duration, run.Phase == "Returning", veil)
end

function UpgradeRevealHandler.Finish(self: UpgradeRevealHandler): ()
	local run = self.Current
	if not run then
		return
	end
	self.Current = nil
	-- Release the page presentation first: a teardown error below must not leave Pages suspended,
	-- which would block purchases and every later reveal for the session.
	if run.Token then
		Pages.EndPresentation(run.Token)
	end
	release(run.Notice)
	if run.Camera then
		run.Camera:Destroy()
	end
	run.Lifetime:Destroy()
	if run.Character == Players.LocalPlayer.Character then
		if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = run.Mouse
		end
		UserInputService.MouseIconEnabled = run.MouseIcon
	end
	if GuiService.SelectedObject == self.Card.Skip then
		local selection = run.Selection
		GuiService.SelectedObject = if selection and selection.Parent then selection else nil
	end
	self.Card:Hide()
end

function UpgradeRevealHandler.Skip(self: UpgradeRevealHandler): ()
	for _, notice in self.Queue do
		release(notice)
	end
	table.clear(self.Queue)
	self:ClearArmed()
	self:BeginReturn()
end

function UpgradeRevealHandler.Cancel(self: UpgradeRevealHandler): ()
	self:Skip()
	self:Finish()
	self.Janitor:Remove("Frame")
end

function UpgradeRevealHandler.Destroy(self: UpgradeRevealHandler): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:Cancel()
	self.Janitor:Destroy()
end

export type UpgradeRevealHandler = typeof(UpgradeRevealHandler) & {
	Janitor: any,
	Card: Card.Card,
	Queue: { Notice },
	Armed: { [string]: Armed },
	Seen: { [string]: number },
	Current: Run?,
	Destroyed: boolean?,
}
return UpgradeRevealHandler :: UpgradeRevealHandler
