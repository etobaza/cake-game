--!strict
-- Cross-platform sprint intent: the player runs while holding Shift or the touch Run button. On a
-- controller a click of L3 toggles running, the console convention, so the stick is never held down;
-- it ends once the player stops moving. The server owns speed and movement locks.

--[[ Services ]]--
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local DataClient = require(ReplicatedStorage.Handlers.DataHandlerClient)
local Flux = require(ReplicatedStorage.Packages.flux)
local InputCues = require(ReplicatedStorage.Shared.Configs.InputCues)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local RunControl = require(ReplicatedStorage.Shared.UI.RunControl)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Constants ]]--
local RUN_ACTION = "CakeSprint"
local TOGGLE_ACTION = "CakeSprintToggle"

--[[ Tables ]]--
local RunHandler = {
	-- The touch control is authored in the mounted HUD.
	dependencies = { "UIHandler", "DataClient" },
}

--[[ Handling ]]--
function RunHandler.OnInit(self: RunHandler): ()
	self.Janitor = Janitor.new()
	self.Running = false
	self.Held = {}
	self.Toggled = false
	self.Still = 0
end

function RunHandler.OnStart(self: RunHandler): ()
	self.Button = UIHandler:GetHud("Controls.Run") :: TextButton
	self.Janitor:Add(RunControl.Bind(self.Button, Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui), "Destroy")
	self.Janitor:Add(self.Button:GetAttributeChangedSignal("TouchLayoutReady"):Connect(function(): ()
		self:Refresh()
	end), "Disconnect")
	-- A touch is held by its own InputObject, so it ends wherever the finger lifts.
	self.Janitor:Add(self.Button.InputBegan:Connect(function(input: InputObject): ()
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.Held[input] = true
			self:Refresh()
		end
	end), "Disconnect")
	self.Janitor:Add(UserInputService.InputEnded:Connect(function(input: InputObject): ()
		if self.Held[input] then
			self.Held[input] = nil
			self:Refresh()
		end
	end), "Disconnect")
	ContextActionService:BindAction(
		RUN_ACTION,
		function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if state == Enum.UserInputState.Cancel then
				self:Reset()
				return Enum.ContextActionResult.Sink
			end
			self.Held[input.KeyCode] = if state == Enum.UserInputState.Begin then true else nil
			self:Refresh()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift
	)
	ContextActionService:BindAction(
		TOGGLE_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				self.Toggled = not self.Toggled
				self.Still = 0
				self:Refresh()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		InputCues.Hints.Keys.Run
	)
	self.Janitor:Add(function(): ()
		ContextActionService:UnbindAction(RUN_ACTION)
		ContextActionService:UnbindAction(TOGGLE_ACTION)
	end)
	self.Janitor:Add(RunService.Heartbeat:Connect(function(deltaTime: number): ()
		self:StepToggle(deltaTime)
	end), "Disconnect")
	local function reset(): ()
		self:Reset()
	end
	self.Janitor:Add(UserInputService.WindowFocusReleased:Connect(reset), "Disconnect")
	self.Janitor:Add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(reset), "Disconnect")
	self.Janitor:Add(UserInputService.TextBoxFocused:Connect(reset), "Disconnect")
	self.Janitor:Add(GuiService.MenuOpened:Connect(reset), "Disconnect")
	self.Janitor:Add(GuiService.MenuClosed:Connect(reset), "Disconnect")
	self.Janitor:Add(GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(reset), "Disconnect")
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Stations" }, function(): ()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
	self.Janitor:Add(Players.LocalPlayer.CharacterRemoving:Connect(reset), "Disconnect")
	local scope = Scope.Run(function(): ()
		Flux(function(): ()
			local _page = Pages.Current()
			Pages.TrackPresenting()
			self:Reset()
		end, true)
	end)
	self.Janitor:Add(scope, "Destroy")
	self:Refresh()
end

function RunHandler.Refresh(self: RunHandler): ()
	local available = Pages.Current:peek() == Pages.Names.None
		and not Pages.Presenting:peek()
		and not GuiService.MenuIsOpen
		and UserInputService:GetFocusedTextBox() == nil
		and GuiService.SelectedObject == nil
	for _, station in DataClient:GetData({ "Stations" }, "Session") or {} do
		if station.State == "Mixing" then
			available = false
			break
		end
	end
	if not available then
		table.clear(self.Held)
		self.Toggled = false
	end
	self:SetRunning(available and (self.Toggled or next(self.Held) ~= nil))
	self.Button.Visible = available
		and UserInputService.PreferredInput == Enum.PreferredInput.Touch
		and self.Button:GetAttribute("TouchLayoutReady") == true
	RunControl.SetRunning(self.Button, self.Running)
end

function RunHandler.Reset(self: RunHandler): ()
	table.clear(self.Held)
	self.Toggled = false
	self:Refresh()
end

-- A toggled run ends once the character has stood still for a moment, as in console games.
function RunHandler.StepToggle(self: RunHandler, deltaTime: number): ()
	if not self.Toggled then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > InputCues.RunToggle.MoveThreshold then
		self.Still = 0
		return
	end
	self.Still += deltaTime
	if self.Still >= InputCues.RunToggle.StopSeconds then
		self.Toggled = false
		self:Refresh()
	end
end

function RunHandler.SetRunning(self: RunHandler, isRunning: boolean): ()
	if self.Running == isRunning then
		return
	end
	self.Running = isRunning
	Bus.Player.SetRunning:Fire(isRunning)
end

function RunHandler.Destroy(self: RunHandler): ()
	self:SetRunning(false)
	self.Janitor:Destroy()
end

export type RunHandler = typeof(RunHandler) & {
	Janitor: any,
	Button: TextButton,
	Running: boolean,
	-- Held keys, and the touch or click holding the Run button.
	Held: { [Enum.KeyCode | InputObject]: boolean? },
	-- The controller's L3 toggle, and how long the character has stood still since.
	Toggled: boolean,
	Still: number,
}

return RunHandler :: RunHandler
