--!strict
-- Tutorial facade: per-player lifetimes, validated presentation intents and accepted action observers.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local CustomerHandler = require(script.Parent.CustomerHandler)
local DataHandler = require(script.Parent.DataHandler)
local DayCycleHandler = require(script.Parent.DayCycleHandler)
local Events = require(ServerScriptService.TutorialEvents)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Run = require(script.Run)
local Sanitize = require(ReplicatedStorage.Shared.Sanitize)
local SessionDefaults = require(ReplicatedStorage.Handlers.DataHandlerClient.Config.SessionData)
local TickHandler = require(script.Parent.TickHandler)

--[[ Tables ]]--
local TutorialHandler = {
	-- Reconcile accepted actions only after the profile, day and guest owners are ready.
	dependencies = { "DataHandler", "DayCycleHandler", "CustomerHandler", "TickHandler" },
}

--[[ Private Functions ]]--
local function release(player: Player): ()
	DayCycleHandler:ReleaseTutorialClock(player)
	CustomerHandler:ReleaseTutorial(player)
end

local function validTopic(id: string): boolean
	for _, topic in Config.Topics do
		if topic.id == id then
			return true
		end
	end
	return false
end

--[[ Handling ]]--
function TutorialHandler.OnInit(self: TutorialHandler): ()
	self.Janitor = Janitor.new()
	self.Runs = {}
	self.LastControl = {}
end

function TutorialHandler.OnStart(self: TutorialHandler): ()
	if not Config.Enabled then
		return
	end
	self.Janitor:Add(
		DataHandler.PlayerReady:Connect(function(player: Player, data: any): ()
			self:Bind(player, data)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player): ()
			self.Janitor:Remove(player)
			self.Runs[player] = nil
			self.LastControl[player] = nil
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		TickHandler.Tick:Connect(function(): ()
			for _, run in self.Runs do
				run:Refresh()
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Events.Action:Connect(function(player: Player, action: string, id: string): ()
			local run = self.Runs[player]
			if run then
				run:Action(action, id)
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Bus.Tutorial.Control.OnServerEvent:Connect(function(player: Player, rawAction: any, rawValue: any): ()
			self:Control(player, rawAction, rawValue)
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		local data = DataHandler:GetData(player)
		if data then
			self:Bind(player, data)
		end
	end
end

function TutorialHandler.Bind(self: TutorialHandler, player: Player, data: any): ()
	if not Config.Enabled then
		return
	end
	if self.Runs[player] then
		return
	end
	local run = Run.new(player, data, release)
	self.Runs[player] = run
	self.Janitor:Add(run, "Destroy", player)
end

function TutorialHandler.Control(self: TutorialHandler, player: Player, rawAction: any, rawValue: any): ()
	local action, value = Sanitize.Id(rawAction), Sanitize.Id(rawValue)
	local run = self.Runs[player]
	if not action or not value or not run then
		return
	end
	local now = os.clock()
	if now - (self.LastControl[player] or -math.huge) < 0.15 then
		return
	end
	self.LastControl[player] = now
	local saved = run.Data.Cloud.Tutorial
	if action == "Skip" and value == "Introduction" then
		run:Finish("Skipped")
	end
	if action == "Collapse" and (value == "true" or value == "false") then
		saved.Collapsed = value == "true"
	end
	if action == "Dismiss" and validTopic(value) then
		saved.Lessons[`Dismissed:{value}`] = true
	end
end

function TutorialHandler.Destroy(self: TutorialHandler): ()
	self.Janitor:Destroy()
end

-- Server-only Cmdr operations rebuild the lifetime, rather than only changing its saved status.
function TutorialHandler.Reset(self: TutorialHandler, player: Player): string
	local data = DataHandler:GetData(player)
	if not data or not self.Runs or not self.Runs[player] then
		return "Tutorial is not ready for this player."
	end
	self.Janitor:Remove(player)
	self.Runs[player] = nil
	self.LastControl[player] = nil
	CustomerHandler:ReleaseTutorial(player)
	data.Cloud.Tutorial = {
		Version = Config.Version,
		Status = "Active",
		Actions = {},
		Lessons = {},
		Collapsed = false,
	}
	-- This is the plain, flat default table, never a DataHandler proxy.
	data.Session.Tutorial = table.clone(SessionDefaults.Tutorial)
	self:Bind(player, data)
	DayCycleHandler:HoldTutorialClock(player)
	if data.Session.Day.Phase == "Shift" then
		CustomerHandler:StartShift(player)
	end
	return `{player.Name}: tutorial reset; current kitchen retained. During Summary, finish Next Day to continue.`
end

function TutorialHandler.Finish(self: TutorialHandler, player: Player, status: string): string
	if status ~= "Completed" and status ~= "Skipped" then
		return "Invalid tutorial status."
	end
	local run = self.Runs and self.Runs[player]
	if not run then
		return "Tutorial is not ready for this player."
	end
	if run.Data.Cloud.Tutorial.Status ~= "Active" then
		return `{player.Name}: tutorial is already {run.Data.Cloud.Tutorial.Status}; use tutorialreset first.`
	end
	run:Finish(status)
	return `{player.Name}: tutorial {status}; guest and clock protection released.`
end

function TutorialHandler.SetCollapsed(self: TutorialHandler, player: Player, collapsed: boolean): string
	local run = self.Runs and self.Runs[player]
	if not run then
		return "Tutorial is not ready for this player."
	end
	run.Data.Cloud.Tutorial.Collapsed = collapsed
	return `{player.Name}: tutorial {if collapsed then "collapsed" else "expanded"}.`
end

function TutorialHandler.GetStatus(self: TutorialHandler, player: Player): string
	local run = self.Runs and self.Runs[player]
	if not run then
		return "Tutorial is not ready for this player."
	end
	local saved, context = run.Data.Cloud.Tutorial, run.Data.Session.Tutorial
	local actions, lessons = {}, {}
	for name, learned in saved.Actions do
		if learned then
			actions[#actions + 1] = name
		end
	end
	for name, learned in saved.Lessons do
		if learned then
			lessons[#lessons + 1] = name
		end
	end
	table.sort(actions)
	table.sort(lessons)
	return table.concat({
		`{player.Name}: {saved.Status}, stage={context.Stage}, version={saved.Version}`,
		`day={run.Data.Session.Day.Phase}, protected={context.Protected}, collapsed={saved.Collapsed}`,
		`recipe={context.RecipeId}, guest={context.GuestId}, table={context.TableId}, seat={context.SeatIndex}`,
		"Actions: " .. table.concat(actions, ", "),
		"Lessons: " .. table.concat(lessons, ", "),
	}, "\n")
end

export type TutorialHandler =
	typeof(TutorialHandler)
	& { Janitor: any, Runs: { [Player]: Run.Run }, LastControl: { [Player]: number } }

return TutorialHandler :: TutorialHandler
