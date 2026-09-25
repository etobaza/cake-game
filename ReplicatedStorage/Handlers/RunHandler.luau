--!strict
-- Cross-platform sprint intent. The server owns speed and movement locks.

--[[ Services ]]--
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local DataClient = require(ReplicatedStorage.Handlers.DataHandlerClient)
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Press = require(ReplicatedStorage.Shared.UI.Press)
local RunControl = require(ReplicatedStorage.Shared.UI.RunControl)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Constants ]]--
local RUN_ACTION = "CakeSprint"

--[[ Tables ]]--
local RunHandler = {
	-- The touch control is authored in the mounted HUD.
	dependencies = { "UIHandler", "DataClient" },
}

--[[ Handling ]]--
function RunHandler.OnInit(self: RunHandler): ()
	self.Janitor = Janitor.new()
	self.Running = false
	self.HeldKeys = {}
	self.Toggle = false
end

function RunHandler.OnStart(self: RunHandler): ()
	self.Button = UIHandler:GetHud("Controls.Run") :: TextButton
	self.Janitor:Add(RunControl.Bind(self.Button, Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui), "Destroy")
	self.Janitor:Add(self.Button:GetAttributeChangedSignal("TouchLayoutReady"):Connect(function(): ()
		self:Refresh()
	end), "Disconnect")
	self.Janitor:Add(
		Press.BindTap(self.Button, function(): ()
			self.Toggle = not self.Toggle
			self:Refresh()
		end),
		"Destroy"
	)
	ContextActionService:BindAction(
		RUN_ACTION,
		function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if state == Enum.UserInputState.Cancel then
				self:Reset()
				return Enum.ContextActionResult.Sink
			end
			if input.KeyCode == Enum.KeyCode.ButtonL3 then
				if state == Enum.UserInputState.Begin then
					self.Toggle = not self.Toggle
				end
			elseif state == Enum.UserInputState.Begin then
				self.HeldKeys[input.KeyCode] = true
			else
				self.HeldKeys[input.KeyCode] = nil
			end
			self:Refresh()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	self.Janitor:Add(function(): ()
		ContextActionService:UnbindAction(RUN_ACTION)
	end)
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
			self:Reset()
		end, true)
	end)
	self.Janitor:Add(scope, "Destroy")
	self:Refresh()
end

function RunHandler.Refresh(self: RunHandler): ()
	local available = Pages.Current:peek() == Pages.Names.None
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
		self.Toggle = false
		table.clear(self.HeldKeys)
	end
	self:SetRunning(available and (self.Toggle or next(self.HeldKeys) ~= nil))
	self.Button.Visible = available
		and UserInputService.PreferredInput == Enum.PreferredInput.Touch
		and self.Button:GetAttribute("TouchLayoutReady") == true
	RunControl.SetRunning(self.Button, self.Running)
end

function RunHandler.Reset(self: RunHandler): ()
	self.Toggle = false
	table.clear(self.HeldKeys)
	self:Refresh()
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
	HeldKeys: { [Enum.KeyCode]: boolean },
	Toggle: boolean,
}

return RunHandler :: RunHandler
