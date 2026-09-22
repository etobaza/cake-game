--!strict
-- Applies an admin-requested fresh start before PlayerReady; paid ownership survives the reset.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Upgrades = require(ReplicatedStorage.Shared.Configs.Registries.Upgrades)

--[[ Constants ]]--
local PRESERVED: { [string]: boolean } = { Passes = true, _productCache = true, Skins = true }

--[[ Tables ]]--
local ProgressReset = {}

--[[ Handling ]]--
-- DataHandler supplies a fresh template copy and the writable Cloud proxy, never the raw save table.
function ProgressReset.Apply(cloud: any, defaults: any): ()
	defaults.Stats.RobuxSpent = if cloud.Stats then cloud.Stats.RobuxSpent or 0 else 0
	defaults.Cash = math.max(defaults.Cash, Upgrades:GetRemainingCost({}))
	for key in cloud do
		if defaults[key] == nil and not PRESERVED[key] then
			cloud[key] = nil
		end
	end
	for key, value in defaults do
		if not PRESERVED[key] then
			cloud[key] = value
		end
	end
end

return ProgressReset
