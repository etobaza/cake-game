--!strict
-- Pantry: the stock of garden ingredients. Flour and sugar are infinite and are not kept here.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local GardenConfig = require(_Configs.Garden)
local Ingredients = require(_Configs.Registries.Ingredients)
local InventoryHandler = require(ServerScriptService.Handlers.InventoryHandler)
local Bus = require(_Shared.Bus)

--[[ Tables ]]--
local PantryHandler = {
	dependencies = { "DataHandler", "InventoryHandler" },
	priority = 70,
}

--[[ Private Functions ]]--
local function GetPantry(player: Player): { [string]: number }?
	local data = DataHandler:GetData(player)
	return data and data.Cloud.Pantry
end

-- An ingredient that runs out leaves the pantry instead of staying at zero.
local function SetAmount(pantry: { [string]: number }, ingredientId: string, amount: number): ()
	if amount > 0 then
		pantry[ingredientId] = amount
	else
		pantry[ingredientId] = nil
	end
end

--[[ Handling ]]--
function PantryHandler.OnStart(self: PantryHandler): ()
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:GrantStarter(player)
	end)

	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			self:GrantStarter(player)
		end
	end
end

-- Moves one pantry item into the player's hands. Staples are unlimited.
function PantryHandler.Take(
	_self: PantryHandler,
	player: Player,
	ingredientId: string,
	sourceId: string?,
	origin: Vector3?
): boolean
	if not Ingredients:Get(ingredientId) then
		return false
	end

	local pantry = GetPantry(player)
	local amount = pantry and pantry[ingredientId] or 0
	if not Ingredients:IsInfinite(ingredientId) and (not pantry or amount <= 0) then
		Bus.Progress.ActionFailed:FireClient(player, "out_of_stock")
		return false
	end

	if not InventoryHandler:Push(player, { Kind = "Ingredient", Id = ingredientId, SourceId = sourceId }, origin) then
		Bus.Progress.ActionFailed:FireClient(player, "hands_full")
		return false
	end

	if Ingredients:IsInfinite(ingredientId) then
		return true
	end

	assert(pantry, "finite ingredients require a pantry")
	SetAmount(pantry, ingredientId, amount - 1)
	return true
end

-- The starter stock is granted exactly once per save, tracked by its own flag: rejoining on day one
-- used to hand it out again.
function PantryHandler.GrantStarter(self: PantryHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data or data.Cloud.StarterPantryGiven then
		return
	end

	data.Cloud.StarterPantryGiven = true

	for ingredientId, amount in GardenConfig.StarterPantry do
		self:Add(player, ingredientId, amount)
	end
end

function PantryHandler.GetAmount(_self: PantryHandler, player: Player, ingredientId: string): number
	local pantry = GetPantry(player)
	return if pantry then pantry[ingredientId] or 0 else 0
end

function PantryHandler.Add(_self: PantryHandler, player: Player, ingredientId: string, amount: number): ()
	if amount <= 0 then
		return
	end

	local pantry = GetPantry(player)
	if not pantry then
		return
	end

	pantry[ingredientId] = (pantry[ingredientId] or 0) + amount
end

function PantryHandler.HasAll(self: PantryHandler, player: Player, ingredients: { [string]: number }): boolean
	for ingredientId, amount in ingredients do
		if Ingredients:IsInfinite(ingredientId) then
			continue
		end

		if self:GetAmount(player, ingredientId) < amount then
			return false
		end
	end

	return true
end

-- Spends the whole ingredient list at once or spends nothing.
function PantryHandler.ConsumeAll(self: PantryHandler, player: Player, ingredients: { [string]: number }): boolean
	if not self:HasAll(player, ingredients) then
		return false
	end

	local pantry = GetPantry(player)
	if not pantry then
		return false
	end

	for ingredientId, amount in ingredients do
		if Ingredients:IsInfinite(ingredientId) then
			continue
		end

		SetAmount(pantry, ingredientId, (pantry[ingredientId] or 0) - amount)
	end

	return true
end

export type PantryHandler = typeof(PantryHandler)

return PantryHandler :: PantryHandler
