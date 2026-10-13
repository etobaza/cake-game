--!strict
-- Reports this client's script errors to the server, which logs them to analytics.
--
-- Only the erroring script's name leaves the client (Shared/ErrorSource), at most once per script per
-- dedupe window. The server re-checks the name and applies its own per-player limits; this side's
-- throttle just keeps a tight error loop from flooding the network.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

--[[ Modules ]]--
local AnalyticsConfig = require(ReplicatedStorage.Shared.Configs.Analytics)
local Bus = require(ReplicatedStorage.Shared.Bus)
local ErrorSource = require(ReplicatedStorage.Shared.ErrorSource)

--[[ Constants ]]--
local CONFIG = AnalyticsConfig.Errors

--[[ Tables ]]--
local ErrorReportHandler = {
	-- Connected in OnInit, early, so errors raised while other handlers start are reported too.
	priority = 1000,
	-- os.clock of the last report per script name.
	Sent = {} :: { [string]: number },
}

--[[ Handling ]]--
function ErrorReportHandler.OnInit(self: ErrorReportHandler): ()
	ScriptContext.Error:Connect(function(message: string, _trace: string, script: Instance?)
		-- A failure in here must not raise another error report about itself.
		pcall(self.Report, self, message, script)
	end)
end

function ErrorReportHandler.Report(self: ErrorReportHandler, message: string, script: Instance?): ()
	local key = ErrorSource.Key(message, script, CONFIG.MaxKeyLength, CONFIG.UnknownKey)
	local now = os.clock()
	local last = self.Sent[key]
	if last and now - last < CONFIG.DedupeSeconds then
		return
	end

	self.Sent[key] = now
	Bus.Diagnostics.ClientError:Fire(key)
end

export type ErrorReportHandler = typeof(ErrorReportHandler)

return ErrorReportHandler
