--!strict
-- Client facade: one Janitor owns the authored tutorial, data/page observers and the shared frame callback.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local DataClient = require(script.Parent.DataHandlerClient)
local Flux = require(ReplicatedStorage.Packages.flux)
local GuestHighlight = require(ReplicatedStorage.Shared.UI.Tutorial.GuestHighlight)
local Interact = require(script.Parent.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Presenter = require(ReplicatedStorage.Shared.UI.Tutorial.Presenter)
local Scenario = require(ReplicatedStorage.Shared.Tutorial.Scenario)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)
local UIHandler = require(script.Parent.UIHandler)

--[[ Tables ]]--
local TutorialHandler = {
	-- Resolve authored targets after the data, screen and world-prompt owners are ready.
	dependencies = { "DataClient", "UIHandler", "InteractHandler", "PromptHandler" },
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
	self.View = Presenter.new(screen, function(text: string): boolean
		if UIHandler.StatusVisible:peek() then
			return false
		end

		UIHandler:Toast(text)
		return true
	end)
	self.Janitor:Add(self.View, "Destroy")
	self.GuestHighlight = GuestHighlight.new(Players.LocalPlayer.UserId)
	self.Janitor:Add(self.GuestHighlight, "Destroy")
	self.Janitor:Add(
		DataClient:SubscribeToAll(function(): ()
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
	local goal = Scenario.Resolve(cloud, session, props, self.Page, now, Pages.CanOpen(Pages.Names.None))

	local completedAt = session.Tutorial.CompletedAt
	if completedAt > 0 and now - completedAt < Config.SuccessSeconds then
		goal = {
			id = "completed",
			title = "Your bakery is ready!",
			hint = "You cooked, served and cleaned your first table. Enjoy your shift!",
			waiting = true,
		}
	end
	self.View:Set(goal, cloud.Tutorial)
	local needsFrame = goal ~= nil or guestId ~= nil
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
end

export type TutorialHandler = typeof(TutorialHandler) & {
	Janitor: any,
	View: any,
	GuestHighlight: GuestHighlight.GuestHighlight,
	Page: string,
	Elapsed: number,
}

return TutorialHandler :: TutorialHandler
