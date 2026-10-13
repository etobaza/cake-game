--!strict
-- Cmdr's Admin gate checks access; LiveEventHandler validates the script and owns the event.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local LiveEventHandler = require(ServerScriptService.Handlers.LiveEventHandler)

--[[ Handling ]]--
return function(_context: any, action: string, scriptId: string?): string
	local verb = string.lower(action)
	if verb == "stop" then
		local _, message = LiveEventHandler:Stop()
		return message
	end
	if verb ~= "start" then
		return `Unknown action "{action}". Use start or stop.`
	end
	local _, message = LiveEventHandler:Start(scriptId or Config.DefaultScript)
	return message
end
