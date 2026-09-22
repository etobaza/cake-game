--!strict
-- Server executor for unlockallupgrades; Cmdr's BeforeRun hook checks Admin access.

--[[ Services ]]--
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Handling ]]--
return function(context: any, player: Player?): string
	local target = player or context.Executor
	if not target or target.Parent ~= Players then
		return "Player is no longer in this server."
	end

	local changed = UpgradeHandler:GrantAll(target)
	if changed == nil then
		return "Player data is not ready. Try again after loading."
	end
	if changed == 0 then
		return `{target.Name} already has every upgrade at maximum level.`
	end
	return `Unlocked {changed} upgrades at maximum level for {target.Name}. No coins spent.`
end
