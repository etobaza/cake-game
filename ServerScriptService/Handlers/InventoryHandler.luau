--!strict
-- The player's single carrying slot. Its one-item limit comes from the HandsLimit stat.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local CarryPolicy = require(_Shared.CarryPolicy)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local GameTypes = require(_Shared.GameTypes)
local Sanitize = require(_Shared.Sanitize)
local Signal = require(_Libs.Signal)
local TutorialEvents = require(ServerScriptService.TutorialEvents)
local UpgradeHandler = require(ServerScriptService.Handlers.UpgradeHandler)

--[[ Constants ]]--
local TOOL: GameTypes.ItemKind = "Tool"
local FUEL: GameTypes.ItemKind = "Fuel"

--[[ Tables ]]--
local InventoryHandler = {
	dependencies = { "DataHandler", "UpgradeHandler" },
	priority = 70,
}

-- Fired when a tool leaves its stand or goes back on it: (player, buildingId). BuildingHandler
-- listens so the world model can disappear for as long as the tool is carried.
InventoryHandler.ToolTaken = Signal() :: Signal.Signal<Player, string>
InventoryHandler.ToolReturned = Signal() :: Signal.Signal<Player, string>

--[[ Private Functions ]]--
local function GetHands(player: Player): { GameTypes.ItemStack }?
	local data = DataHandler:GetData(player)
	return data and data.Session.Hands
end

--[[ Handling ]]--
function InventoryHandler.OnStart(_self: InventoryHandler): ()
	-- BuildingHandler owns all ranged world interaction listeners.
end

function InventoryHandler.GetCount(_self: InventoryHandler, player: Player): number
	local hands = GetHands(player)
	return if hands then #hands else 0
end

function InventoryHandler.HasRoom(self: InventoryHandler, player: Player): boolean
	local count = self:GetCount(player)
	return count < UpgradeHandler:GetStat(player, "HandsLimit")
		or (count == 1 and CarryPolicy.CanReplace(self:Peek(player)))
end

function InventoryHandler.Push(
	self: InventoryHandler,
	player: Player,
	item: GameTypes.ItemStack,
	origin: Vector3?
): boolean
	local hands = GetHands(player)
	if not hands or not self:HasRoom(player) then
		return false
	end

	-- Replace only after the caller accepted the pickup. One write restores the previous source
	-- and replicates the new appearance without an intermediate empty hand.
	local index = if #hands == 1 and CarryPolicy.CanReplace(hands[1]) then 1 else #hands + 1
	hands[index] = {
		Kind = item.Kind,
		Id = item.Id,
		SourceId = item.SourceId,
		PickupOrigin = origin,
		PickupAt = if origin then workspace:GetServerTimeNow() else nil,
	}

	return true
end

-- Takes the carried item; the array shape is retained for the shared Session contract.
function InventoryHandler.Pop(_self: InventoryHandler, player: Player): GameTypes.ItemStack?
	local hands = GetHands(player)
	if not hands or #hands == 0 then
		return nil
	end

	local index = #hands
	local item = hands[index]
	hands[index] = nil

	return item
end

function InventoryHandler.Peek(_self: InventoryHandler, player: Player): GameTypes.ItemStack?
	local hands = GetHands(player)
	return if hands then hands[#hands] else nil
end

-- Server-owned counter exchange: replace the held dish without needing a spare carrying slot.
function InventoryHandler.ExchangeDish(
	_self: InventoryHandler,
	player: Player,
	recipeId: string,
	origin: Vector3?,
	leftover: boolean?
): string?
	local hands = GetHands(player)
	if not hands then
		return nil
	end
	local count = #hands
	local held = hands[count]
	if not held or (held.Kind ~= "Dish" and held.Kind ~= "Leftover") then
		return nil
	end
	local previous = held.Id
	hands[count] = {
		Kind = if leftover then "Leftover" else "Dish",
		Id = recipeId,
		PickupOrigin = origin,
		PickupAt = workspace:GetServerTimeNow(),
	}
	return previous
end

-- Index of the first matching item: with no id given, any item of that kind will do.
function InventoryHandler.FindIndex(
	_self: InventoryHandler,
	player: Player,
	kind: GameTypes.ItemKind,
	id: string?
): number?
	local hands = GetHands(player)
	if not hands then
		return nil
	end

	for index = 1, #hands do
		local item = hands[index]
		if item.Kind == kind and (not id or item.Id == id) then
			return index
		end
	end

	return nil
end

function InventoryHandler.CountMatching(
	_self: InventoryHandler,
	player: Player,
	kind: GameTypes.ItemKind,
	id: string?
): number
	local hands = GetHands(player)
	if not hands then
		return 0
	end
	local count = 0
	for _, item in hands do
		if item.Kind == kind and (not id or item.Id == id) then
			count += 1
		end
	end

	return count
end

function InventoryHandler.RemoveAt(_self: InventoryHandler, player: Player, index: number): GameTypes.ItemStack?
	local hands = GetHands(player)
	if not hands then
		return nil
	end

	return DataList.RemoveAt(hands, index)
end

function InventoryHandler.TakeMatching(
	self: InventoryHandler,
	player: Player,
	kind: GameTypes.ItemKind,
	id: string?
): GameTypes.ItemStack?
	local index = self:FindIndex(player, kind, id)
	return if index then self:RemoveAt(player, index) else nil
end

function InventoryHandler.Clear(_self: InventoryHandler, player: Player): ()
	local hands = GetHands(player)
	if not hands then
		return
	end

	for index = #hands, 1, -1 do
		hands[index] = nil
	end
end

-- World ownership and distance are checked by BuildingHandler before this mutates the hands.
function InventoryHandler.Discard(self: InventoryHandler, player: Player): boolean
	local held = self:Peek(player)
	if not held then
		return false
	end

	if held.Kind == TOOL then
		Bus.Progress.ActionFailed:FireClient(player, "put_broom_back")
		return false
	end

	self:Pop(player)

	return true
end

-- BuildingHandler validates the owned dispenser and range before allowing a return.
function InventoryHandler.ReturnIngredient(
	self: InventoryHandler,
	player: Player,
	sourceId: string,
	ingredientId: string
): boolean
	if not CarryPolicy.CanReturn(self:Peek(player), sourceId, ingredientId) then
		return false
	end
	self:Pop(player)
	return true
end

function InventoryHandler.TakeTool(self: InventoryHandler, player: Player, buildingId: any, origin: Vector3?): ()
	local id = Sanitize.Id(buildingId)
	local toolId = id and BuildingsConfig.GetToolId(id)
	if not id or not toolId then
		return
	end

	if self:FindIndex(player, TOOL, toolId) then
		return
	end

	if not self:HasRoom(player) then
		Bus.Progress.ActionFailed:FireClient(player, "hands_full")
		return
	end

	if self:Push(player, { Kind = TOOL, Id = toolId }, origin) then
		self.ToolTaken:Fire(player, id)
	end
end

-- One visit to the woodpile is one log, and the single slot forces it to be used before another trip.
function InventoryHandler.TakeFirewood(
	self: InventoryHandler,
	player: Player,
	buildingId: string,
	origin: Vector3?
): boolean
	if not BuildingsConfig.GivesFuel(buildingId) then
		return false
	end

	if not self:HasRoom(player) then
		Bus.Progress.ActionFailed:FireClient(player, "hands_full")
		return false
	end

	return self:Push(player, { Kind = FUEL, Id = BuildingsConfig.FuelItemId }, origin)
end

function InventoryHandler.ReturnTool(self: InventoryHandler, player: Player, buildingId: any): ()
	local id = Sanitize.Id(buildingId)
	local toolId = id and BuildingsConfig.GetToolId(id)
	if not id or not toolId then
		return
	end

	if self:TakeMatching(player, TOOL, toolId) then
		self.ToolReturned:Fire(player, id)
		TutorialEvents.Action:Fire(player, "ReturnTool", toolId)
	end
end

export type InventoryHandler = typeof(InventoryHandler)

return InventoryHandler :: InventoryHandler
