--!strict
-- Shared ingredient guidance; saved pantry stock is a fallback to physical greenhouse produce.

--[[ Modules ]]--
local Garden = require(script.Parent.Configs.Garden)
local Upgrades = require(script.Parent.Configs.Registries.Upgrades)

--[[ Tables ]]--
local GardenSource = {}

--[[ Handling ]]--
function GardenSource.Find(ingredientId: string): (string?, any?)
	for id, source in Garden.Sources do
		if source.Produce == ingredientId then
			return id, source
		end
	end
	return nil, nil
end

function GardenSource.Describe(ingredientId: string, cloud: any): string
	local pantry = cloud.Pantry[ingredientId] or 0
	if pantry > 0 then
		return `Pantry {pantry} · tap to take`
	end
	local id, source = GardenSource.Find(ingredientId)
	if not id or not source then
		return "Kitchen"
	end
	local upgrade = Upgrades:Get(source.Upgrade)
	local name = if upgrade then upgrade.name else source.Folder
	if (cloud.Base.Upgrades[source.Upgrade] or 0) <= 0 then
		return `Buy {name}`
	end
	local node = cloud.Garden[source.Group][id]
	if node and node.Stock > 0 then
		return `{name} · ready {node.Stock}`
	end
	if not node or (node.CareRemaining <= 0 and node.CleanDay ~= cloud.Day and source.Care ~= "Hive") then
		return `{if source.Care == "Animal" then "Brush" else "Water"} {name}`
	end
	return `{name} · growing`
end

return GardenSource
