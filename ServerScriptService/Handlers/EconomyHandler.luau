--!strict
-- Wallet and levels: the only place where the player's coins and XP change.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local Economy = require(_Configs.Economy)
local LoggerUtil = require(_Libs.Logger)
local Products = require(_Configs.Registries.Products)
local Progression = require(_Configs.Progression)
local Recipes = require(_Configs.Registries.Recipes)
local Signal = require(_Libs.Signal)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "EconomyHandler" })

--[[ Tables ]]--
local EconomyHandler = {
	dependencies = { "DataHandler" },
	priority = 90,
}

-- Fired after a level up, with the new level and the recipes it unlocked.
EconomyHandler.LevelUp = Signal() :: Signal.Signal<Player, number, { string }>

--[[ Private Functions ]]--
local function GetCloud(player: Player): any?
	local data = DataHandler:GetData(player)
	return data and data.Cloud
end

--[[ Handling ]]--
function EconomyHandler.OnStart(self: EconomyHandler): ()
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:GrantStarterBonus(player)
	end)
end

-- On the very first day the starter recipes count as new too: otherwise the novelty bonus is unreachable.
-- Guarded by its own flag rather than by "is the table still empty": that question cannot be asked
-- of replicated data, and the answer was always yes.
function EconomyHandler.GrantStarterBonus(self: EconomyHandler, player: Player): ()
	local cloud = GetCloud(player)
	if not cloud or cloud.StarterRecipesMarked then
		return
	end

	cloud.StarterRecipesMarked = true

	for _, recipe in Recipes:GetUnlockedAt(1) do
		self:MarkRecipeNew(player, recipe.id)
	end
end

function EconomyHandler.GetLevel(_self: EconomyHandler, player: Player): number
	local cloud = GetCloud(player)
	return if cloud then cloud.Level else 1
end

function EconomyHandler.GetCash(_self: EconomyHandler, player: Player): number
	local cloud = GetCloud(player)
	return if cloud then cloud.Cash else 0
end

--- Adds coins, multiplied by whatever passes the player owns.
--- The multiplier lands here rather than at the till: this is the one place coins are created, so a
--- pass that pays more pays more on everything, and there is no second path to forget about.
function EconomyHandler.AddCash(_self: EconomyHandler, player: Player, amount: number): ()
	if amount <= 0 then
		return
	end

	local cloud = GetCloud(player)
	if not cloud then
		return
	end

	local multiplier = Products:GetCashMultiplier(cloud.Passes)

	cloud.Cash = math.round((cloud.Cash + amount * multiplier) * 100) / 100
end

-- Spends coins if there are enough. Returns false without touching the data.
function EconomyHandler.TrySpend(_self: EconomyHandler, player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local cloud = GetCloud(player)
	if not cloud or cloud.Cash < amount then
		return false
	end

	cloud.Cash = math.round((cloud.Cash - amount) * 100) / 100

	return true
end

-- Grants XP and raises levels while there is enough XP. Unlocked recipes follow from the level.
-- Returns the delta actually applied: a penalty never takes XP below zero, and the day summary must
-- show the same thing the player really got.
function EconomyHandler.AwardXP(self: EconomyHandler, player: Player, amount: number): number
	local cloud = GetCloud(player)
	if not cloud then
		return 0
	end

	local applied = math.max(amount, -cloud.XP)
	cloud.XP = cloud.XP + applied

	local required = Progression.GetXPToNext(cloud.Level)
	while required and cloud.XP >= required do
		cloud.XP = cloud.XP - required
		cloud.Level = cloud.Level + 1

		self:AnnounceLevel(player, cloud.Level)
		required = Progression.GetXPToNext(cloud.Level)
	end

	-- At max level there is nowhere to accumulate XP.
	if not required then
		cloud.XP = 0
	end

	return applied
end

function EconomyHandler.AnnounceLevel(self: EconomyHandler, player: Player, level: number): ()
	local unlocked: { string } = {}
	for _, recipe in Recipes:GetUnlockedAt(level) do
		unlocked[#unlocked + 1] = recipe.id
		self:MarkRecipeNew(player, recipe.id)
	end

	Logger:Info(`{player.Name} reached level {level}, recipes unlocked: {#unlocked}`)

	Bus.Day.LevelUp:FireClient(player, level)
	EconomyHandler.LevelUp:Fire(player, level, unlocked)

	local stage = Progression.GetStoryStage(level)
	if not stage then
		return
	end

	local cloud = GetCloud(player)
	if not cloud or cloud.StoryStage >= stage then
		return
	end

	cloud.StoryStage = stage
	Bus.Day.StoryUnlocked:FireClient(player, stage)
end

-- A freshly unlocked recipe gives a tip bonus for a few days.
function EconomyHandler.MarkRecipeNew(_self: EconomyHandler, player: Player, recipeId: string): ()
	local cloud = GetCloud(player)
	if not cloud then
		return
	end

	cloud.NewRecipeUntilDay[recipeId] = cloud.Day + Economy.NewRecipeBonusDays
end

function EconomyHandler.IsRecipeNew(_self: EconomyHandler, player: Player, recipeId: string): boolean
	local cloud = GetCloud(player)
	if not cloud then
		return false
	end

	local expiresDay = cloud.NewRecipeUntilDay[recipeId]

	return expiresDay ~= nil and cloud.Day <= expiresDay
end

-- The recipe is available by level; there is no separate list of unlocked recipes in the save.
function EconomyHandler.IsRecipeUnlocked(self: EconomyHandler, player: Player, recipeId: string): boolean
	local recipe = Recipes:Get(recipeId)
	if not recipe then
		return false
	end

	return recipe.unlockLevel <= self:GetLevel(player)
end

export type EconomyHandler = typeof(EconomyHandler)

return EconomyHandler :: EconomyHandler
