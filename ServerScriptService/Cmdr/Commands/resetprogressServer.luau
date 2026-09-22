--!strict
-- Cmdr's Admin gate authorizes the request; DataHandler owns profile lifetime and reset ordering.

--[[ Services ]]--
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local DataHandler = require(ServerScriptService.Handlers.DataHandler)

--[[ Handling ]]--
return function(context: any, player: Player?): string
	local target = player or context.Executor
	if not target or target.Parent ~= Players then
		return "Player is no longer in this server."
	end
	return DataHandler:RequestProgressReset(target)
end
