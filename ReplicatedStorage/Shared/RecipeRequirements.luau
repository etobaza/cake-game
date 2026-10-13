--!strict
-- What a recipe still needs before the player can make it: its station and the upgrades behind its
-- renewable ingredient sources (a garden plant, a farm animal). Cooking itself is not gated (pantry
-- stock can still be used), but the day menu only takes dishes the player can always supply, and
-- guests only order those.

local BaseStats = require(script.Parent.Configs.BaseStats)
local Buildings = require(script.Parent.Configs.Buildings)
local GardenSource = require(script.Parent.GardenSource)
local Recipes = require(script.Parent.Configs.Registries.Recipes)
local Upgrades = require(script.Parent.Configs.Registries.Upgrades)

local RecipeRequirements = {}

function RecipeRequirements.GetMissing(recipe: Recipes.RecipeEntry, levels: { [string]: number }): { string }
	local missing: { [string]: boolean } = {}
	local kind = (Buildings.Kinds :: { [string]: Buildings.Kind })[recipe.station]
	if kind and kind.Stat and BaseStats[kind.Stat :: BaseStats.StatKey] == 0 then
		for _, upgrade in Upgrades:Values() do
			if upgrade.stat == kind.Stat and upgrade.perLevel > 0 and (levels[upgrade.id] or 0) == 0 then
				missing[upgrade.id] = true
			end
		end
	end
	for ingredientId in recipe.ingredients do
		local _, source = GardenSource.Find(ingredientId)
		if source and (levels[source.Upgrade] or 0) == 0 then
			missing[source.Upgrade] = true
		end
	end
	local ids: { string } = {}
	for id in missing do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--- Whether every station and ingredient source of `recipe` is owned, so guests may order it.
function RecipeRequirements.IsObtainable(recipe: Recipes.RecipeEntry, levels: { [string]: number }): boolean
	return #RecipeRequirements.GetMissing(recipe, levels) == 0
end

function RecipeRequirements.Describe(ids: { string }, limit: number?): string
	local names: { string } = {}
	for index, id in ids do
		if limit and index > limit then
			table.insert(names, `+{#ids - limit} more`)
			break
		end
		table.insert(names, Upgrades:GetDisplayName(id, 0))
	end
	return if #names > 0 then `Upgrades: {table.concat(names, ", ")}` else ""
end

return RecipeRequirements
