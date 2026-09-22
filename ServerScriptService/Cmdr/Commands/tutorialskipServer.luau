--!strict
-- Server executor for tutorialskip; Cmdr's BeforeRun hook checks TutorialDebug access.

--[[ Services ]]--
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local TutorialHandler = require(ServerScriptService.Handlers.TutorialHandler)

--[[ Handling ]]--
return function(context: any, player: Player?): string
	local target = player or context.Executor
	if not target or target.Parent ~= Players then
		return "Player is no longer in this server."
	end
	return TutorialHandler:Finish(target, "Skipped")
end
