--!strict
-- Players always run: the client asks for running whenever free movement is available and drops it
-- while a page, menu, focused text box, gamepad selection or mixing station holds the player. There is
-- no sprint input. The server owns speed and movement locks.

--[[ Services ]]--
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
local RunControl = require(ReplicatedStorage.Shared.UI.RunControl)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Tables ]]--
local RunHandler = {
	-- The touch control is authored in the mounted HUD.
	dependencies = { "UIHandler", "DataClient" },
}

--[[ Handling ]]--
function RunHandler.OnInit(self: RunHandler): ()
	self.Janitor = Janitor.new()
	self.Running = false
end

function RunHandler.OnStart(self: RunHandler): ()
	-- The authored Run button stays hidden; RunControl still fits it beside the jump control because
	-- its published TouchReserve keeps HudLayout's order row and XP toast clear of the touch corner.
	local button = UIHandler:GetHud("Controls.Run") :: TextButton
	button.Visible = false
	self.Janitor:Add(RunControl.Bind(button, Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui), "Destroy")
	-- The authored controller hint row still carries a Run (L3) entry from the old toggle.
	local runHint = UIHandler:GetHud("Controls.GamepadHint"):FindFirstChild("Run")
	if runHint and runHint:IsA("GuiObject") then
		runHint.Visible = false
	end

	local function refresh(): ()
		self:Refresh()
	end
	self.Janitor:Add(UserInputService.WindowFocusReleased:Connect(refresh), "Disconnect")
	self.Janitor:Add(UserInputService.TextBoxFocused:Connect(refresh), "Disconnect")
	self.Janitor:Add(UserInputService.TextBoxFocusReleased:Connect(refresh), "Disconnect")
	self.Janitor:Add(GuiService.MenuOpened:Connect(refresh), "Disconnect")
	self.Janitor:Add(GuiService.MenuClosed:Connect(refresh), "Disconnect")
	self.Janitor:Add(GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(refresh), "Disconnect")
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Stations" }, function(): ()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
	self.Janitor:Add(Players.LocalPlayer.CharacterAdded:Connect(refresh), "Disconnect")
	local scope = Scope.Run(function(): ()
		Flux(function(): ()
			local _page = Pages.Current()
			Pages.TrackPresenting()
			self:Refresh()
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
	self:SetRunning(available)
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
	Running: boolean,
}

return RunHandler :: RunHandler
