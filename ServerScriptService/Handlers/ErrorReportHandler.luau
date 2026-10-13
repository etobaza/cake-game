--!strict
-- Script errors as Creator Dashboard custom events (Configs/Analytics.Errors), so a broken build shows
-- up as a spike per script without waiting for player reports.
--
-- Server errors come from this server's ScriptContext; client errors arrive from the client
-- ErrorReportHandler as a bare script name. The event carries the realm and that name only. The
-- dashboard's own error report keeps the messages and stack traces.
--
-- AnalyticsService needs a player for every event. Client errors belong to their sender; a server
-- error is attributed to the first player in the server list, and is dropped while it is empty.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

--[[ Modules ]]--
local AnalyticsConfig = require(ReplicatedStorage.Shared.Configs.Analytics)
local AnalyticsHandler = require(ServerScriptService.Handlers.AnalyticsHandler)
local Bus = require(ReplicatedStorage.Shared.Bus)
local ErrorSource = require(ReplicatedStorage.Shared.ErrorSource)

--[[ Types ]]--
type ClientState = {
	-- os.clock of the last report per script name.
	Sent: { [string]: number },
	WindowStartedAt: number,
	WindowCount: number,
}

--[[ Constants ]]--
local CONFIG = AnalyticsConfig.Errors
local RATE_WINDOW_SECONDS = 60
-- Containers whose scripts can run on a client; a client may only name one of these.
local CLIENT_ROOTS: { Instance } = { ReplicatedFirst, ReplicatedStorage, StarterGui, StarterPlayer }

--[[ Tables ]]--
local ErrorReportHandler = {
	dependencies = { "AnalyticsHandler" },
	priority = 0,
	ClientScripts = {} :: { [string]: true },
	Clients = {} :: { [Player]: ClientState },
	-- os.clock of the last report per server script name.
	ServerSent = {} :: { [string]: number },
}

--[[ Private Functions ]]--
local function isDuplicate(sent: { [string]: number }, key: string, now: number): boolean
	local last = sent[key]
	if last and now - last < CONFIG.DedupeSeconds then
		return true
	end

	sent[key] = now
	return false
end

--[[ Handling ]]--
function ErrorReportHandler.OnStart(self: ErrorReportHandler): ()
	for _, root in CLIENT_ROOTS do
		for _, instance in root:GetDescendants() do
			if instance:IsA("LuaSourceContainer") then
				self.ClientScripts[ErrorSource.Key("", instance, CONFIG.MaxKeyLength, CONFIG.UnknownKey)] = true
			end
		end
	end

	ScriptContext.Error:Connect(function(message: string, _trace: string, script: Instance?)
		-- A failure in here must not raise another error report about itself.
		pcall(self.ReportServer, self, message, script)
	end)

	Bus.Diagnostics.ClientError.OnServerEvent:Connect(function(player: Player, rawKey: any)
		self:ReportClient(player, rawKey)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.Clients[player] = nil
	end)
end

function ErrorReportHandler.ReportServer(self: ErrorReportHandler, message: string, script: Instance?): ()
	local reporter = Players:GetPlayers()[1]
	if not reporter then
		return
	end

	local key = ErrorSource.Key(message, script, CONFIG.MaxKeyLength, CONFIG.UnknownKey)
	if isDuplicate(self.ServerSent, key, os.clock()) then
		return
	end

	AnalyticsHandler:LogCustom(reporter, CONFIG.Event, 1, "Server", key)
end

--- A client's report is only a name: anything that is not a script the server ships to clients is
--- counted as Other, so a modified client cannot invent new dashboard values.
function ErrorReportHandler.ReportClient(self: ErrorReportHandler, player: Player, rawKey: any): ()
	if typeof(rawKey) ~= "string" then
		return
	end

	local state = self.Clients[player]
	local now = os.clock()
	if not state then
		state = { Sent = {}, WindowStartedAt = now, WindowCount = 0 }
		self.Clients[player] = state
	end

	if now - state.WindowStartedAt >= RATE_WINDOW_SECONDS then
		state.WindowStartedAt = now
		state.WindowCount = 0
	end
	if state.WindowCount >= CONFIG.ClientPerMinute then
		return
	end

	local known = #rawKey <= CONFIG.MaxKeyLength and (self.ClientScripts[rawKey] or rawKey == CONFIG.UnknownKey)
	local key = if known then rawKey else CONFIG.OtherKey
	if isDuplicate(state.Sent, key, now) then
		return
	end

	state.WindowCount += 1
	AnalyticsHandler:LogCustom(player, CONFIG.Event, 1, "Client", key)
end

export type ErrorReportHandler = typeof(ErrorReportHandler)

return ErrorReportHandler
