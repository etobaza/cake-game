--!strict
-- Cmdr loads this initializer on both sides; the server owns command authorization.

--[[ Services ]]--
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Handling ]]--
return function(registry: any): ()
	-- Never resolve server-only modules while Cmdr initializes its client copy.
	if not RunService:IsServer() then
		return
	end
	local AdminRegistry = require(ServerScriptService.Cmdr.Admin)
	registry:RegisterHook("BeforeRun", function(context: any): string?
		if context.Group ~= "Admin" and context.Group ~= "TutorialDebug" then
			return nil
		end
		local executor = context.Executor
		if executor and context.Group == "TutorialDebug" and RunService:IsStudio() then
			return nil
		end
		if executor and AdminRegistry:IsAdmin(executor.UserId) then
			return nil
		end
		return "You do not have permission to run this command."
	end)
end
