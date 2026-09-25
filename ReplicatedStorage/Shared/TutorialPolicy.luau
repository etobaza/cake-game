--!strict
-- Shared read policy. No handler dependencies: days, guests and stations use the same protection.

--[[ Modules ]]--
local Config = require(script.Parent.Configs.Tutorial)
local GardenSource = require(script.Parent.GardenSource)
local Ingredients = require(script.Parent.Configs.Registries.Ingredients)
local Recipes = require(script.Parent.Configs.Registries.Recipes)

--[[ Tables ]]--
local TutorialPolicy = {}

--[[ Handling ]]--
function TutorialPolicy.IsActive(cloud: any): boolean
	return Config.Enabled and cloud.Tutorial ~= nil and cloud.Tutorial.Status == "Active"
end

function TutorialPolicy.NeedsFloor(cloud: any): boolean
	if not TutorialPolicy.IsActive(cloud) or not Config.IntroCleanup then
		return false
	end
	local actions = cloud.Tutorial.Actions
	-- Existing introductions keep their learned cooking progress after this addition.
	return not (
		actions.PreparedFloor or actions.RecipeSelected or actions.Mixed or actions.CollectedDish or actions.Served
	)
end

function TutorialPolicy.Migrate(data: any): ()
	local saved = data.Cloud.Tutorial
	if saved.Version >= Config.Version then
		return
	end
	if saved.Version == 0 then
		saved.Status = if data.Cloud.Day > 1 then "Completed" else "Active"
	end
	saved.Version = Config.Version
end

function TutorialPolicy.BurnSeconds(cloud: any, normal: number): number
	if TutorialPolicy.IsActive(cloud) and not cloud.Tutorial.Actions.CollectedDish then
		return math.max(normal, Config.FirstBakeGrace)
	end
	return normal
end

function TutorialPolicy.Recipe(session: any): string?
	local context = session.Tutorial
	if context and context.Protected and context.GuestId ~= "" and context.RecipeId ~= "" then
		return context.RecipeId
	end
	for _, item in session.Hands do
		if item.Kind == "Dish" or item.Kind == "Dough" then
			return item.Id
		end
	end
	for _, station in session.Stations do
		if station.RecipeId and station.State ~= "Idle" then
			return station.RecipeId
		end
	end
	for _, recipeId in session.Display do
		return recipeId
	end
	local selected = session.Cooking.SelectedRecipeId
	if selected and Recipes:Get(selected) then
		return selected
	end
	for _, recipeId in session.Day.Menu do
		if recipeId == Config.RecommendedRecipe then
			return recipeId
		end
	end
	return session.Day.Menu[1]
end

-- Do not lock an early guest to an idle selection whose produce cannot be replaced.
function TutorialPolicy.CanPrepare(cloud: any, session: any, recipeId: string): boolean
	local recipe = Recipes:Get(recipeId)
	if not recipe then
		return false
	end
	for _, item in session.Hands do
		if item.Id == recipeId and (item.Kind == "Dish" or item.Kind == "Dough") then
			return true
		end
	end
	for _, dish in session.Display do
		if dish == recipeId then
			return true
		end
	end
	for _, station in session.Stations do
		if station.RecipeId == recipeId and station.State ~= "Idle" and station.State ~= "Burnt" then
			return true
		end
	end
	for id, needed in recipe.ingredients do
		if Ingredients:IsInfinite(id) then
			continue
		end
		local _, source = GardenSource.Find(id)
		if source and (cloud.Base.Upgrades[source.Upgrade] or 0) > 0 then
			continue
		end
		local amount = cloud.Pantry[id] or 0
		for _, item in session.Hands do
			if item.Kind == "Ingredient" and item.Id == id then
				amount += 1
			end
		end
		for _, station in session.Stations do
			local selectedMixer = station.Kind == "Mixer" and session.Cooking.SelectedRecipeId == recipeId
			amount += if station.RecipeId == recipeId or selectedMixer then station.Loaded[id] or 0 else 0
		end
		for _, delivered in cloud.GardenCart.Queue do
			if delivered == id then
				amount += 1
			end
		end
		if cloud.GardenCart.Payload == id then
			amount += 1
		end
		if amount < needed then
			return false
		end
	end
	return true
end

function TutorialPolicy.FirstOrder(cloud: any, session: any): string?
	local preferred = TutorialPolicy.Recipe(session)
	if preferred and TutorialPolicy.CanPrepare(cloud, session, preferred) then
		return preferred
	end
	for _, recipeId in session.Day.Menu do
		if TutorialPolicy.CanPrepare(cloud, session, recipeId) then
			return recipeId
		end
	end
	return nil
end

return TutorialPolicy
