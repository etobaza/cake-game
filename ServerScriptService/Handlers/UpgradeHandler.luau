--!strict
-- Upgrades: the purchase and the only place where the player's numeric stats are computed.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BaseStats = require(_Configs.BaseStats)
local Bus = require(_Shared.Bus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local LoggerUtil = require(_Libs.Logger)
local Products = require(_Configs.Registries.Products)
local Sanitize = require(_Shared.Sanitize)
local Signal = require(_Libs.Signal)
local Upgrades = require(_Configs.Registries.Upgrades)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "UpgradeHandler" })

--[[ Tables ]]--
local UpgradeHandler = {
	dependencies = { "DataHandler", "EconomyHandler" },
	priority = 80,
}

-- Fired after upgrades changed the player's stats: slot counts must be rebuilt.
UpgradeHandler.StatsChanged = Signal() :: Signal.Signal<Player>

--[[ Private Functions ]]--
local function GetUpgradeLevels(player: Player): { [string]: number }?
	local data = DataHandler:GetData(player)
	return data and data.Cloud.Base.Upgrades
end

--[[ Handling ]]--
function UpgradeHandler.OnInit(self: UpgradeHandler): ()
	self.StatCache = {}
end

function UpgradeHandler.OnStart(self: UpgradeHandler): ()
	Bus.Progress.BuyUpgrade.OnServerEvent:Connect(function(player: Player, upgradeId: any, purchaseLevel: any)
		local id = Sanitize.Id(upgradeId)
		if not id or typeof(purchaseLevel) ~= "number" or purchaseLevel % 1 ~= 0 or purchaseLevel < 1 then
			return
		end

		self:TryBuy(player, id, purchaseLevel)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.StatCache[player] = nil
	end)
end

function UpgradeHandler.GetLevel(_self: UpgradeHandler, player: Player, upgradeId: string): number
	local levels = GetUpgradeLevels(player)
	return if levels then levels[upgradeId] or 0 else 0
end

-- Base stat value plus the contribution of every bought upgrade. The result is cached until a purchase.
function UpgradeHandler.GetStat(self: UpgradeHandler, player: Player, statKey: BaseStats.StatKey): number
	local cached = self.StatCache[player]
	if cached and cached[statKey] then
		return cached[statKey]
	end

	local value = BaseStats[statKey] :: number
	local levels = GetUpgradeLevels(player)
	local data = DataHandler:GetData(player)
	-- Character setup may ask before the profile arrives. Never cache that temporary baseline.
	if not data then
		return value
	end

	-- A pass that raises a stat is one more term in the same sum the upgrades feed, so it is cached
	-- and invalidated exactly like they are.
	if data then
		value += Products:GetStatBonus(data.Cloud.Passes, statKey)
	end

	if levels then
		for upgradeId, level in levels do
			local entry = Upgrades:Get(upgradeId)
			if not entry or entry.stat ~= statKey then
				continue
			end

			value += entry.perLevel * math.min(level, entry.maxLevel)
		end
	end

	if not cached then
		cached = {}
		self.StatCache[player] = cached
	end
	(cached :: { [string]: number })[statKey] = value

	return value
end

-- Pass synchronization changes stat inputs without buying an upgrade.
function UpgradeHandler.Invalidate(self: UpgradeHandler, player: Player): ()
	self.StatCache[player] = nil
	self.StatsChanged:Fire(player)
end

-- Stat flag like AutoWater: 0 means no, above zero means yes.
function UpgradeHandler.HasStat(self: UpgradeHandler, player: Player, statKey: BaseStats.StatKey): boolean
	return self:GetStat(player, statKey) > 0
end

function UpgradeHandler.TryBuy(self: UpgradeHandler, player: Player, upgradeId: string, purchaseLevel: number?): boolean
	local entry = Upgrades:Get(upgradeId)
	if not entry then
		Bus.Progress.ActionFailed:FireClient(player, "unknown_upgrade")
		return false
	end

	if EconomyHandler:GetLevel(player) < entry.unlockLevel then
		Bus.Progress.ActionFailed:FireClient(player, "level_too_low")
		return false
	end

	-- Tree order: a node opens only after the one it grows from has been bought at least once.
	if Upgrades:GetMissingRequirement(entry, GetUpgradeLevels(player) or {}) then
		Bus.Progress.ActionFailed:FireClient(player, "needs_parent")
		return false
	end

	local level = self:GetLevel(player, upgradeId)
	-- Separate UI cells buy one exact level. A stale/repeated click cannot purchase the next cell.
	if purchaseLevel ~= nil and purchaseLevel ~= level + 1 then
		Bus.Progress.ActionFailed:FireClient(player, if purchaseLevel <= level then "max_level" else "needs_parent")
		return false
	end
	local cost = Upgrades:GetCost(upgradeId, level)
	if not cost then
		Bus.Progress.ActionFailed:FireClient(player, "max_level")
		return false
	end

	if not EconomyHandler:TrySpend(player, cost) then
		Bus.Progress.ActionFailed:FireClient(player, "not_enough_coins")
		return false
	end

	local levels = GetUpgradeLevels(player)
	if not levels then
		return false
	end

	levels[upgradeId] = level + 1
	self.StatCache[player] = nil

	Logger:Info(`{player.Name} bought {upgradeId} to level {level + 1} for {cost}`)
	UpgradeHandler.StatsChanged:Fire(player)

	return true
end

-- Server-only admin grant. Notify observers once, after every level and the stat cache agree.
function UpgradeHandler.GrantAll(self: UpgradeHandler, player: Player): number?
	local levels = GetUpgradeLevels(player)
	if not levels then
		return nil
	end

	local changed = 0
	for _, entry in Upgrades:Values() do
		if (levels[entry.id] or 0) >= entry.maxLevel then
			continue
		end
		levels[entry.id] = entry.maxLevel
		changed += 1
	end
	if changed == 0 then
		return 0
	end

	self.StatCache[player] = nil
	Logger:Info(`Granted {changed} upgrades at maximum level to {player.Name}`)
	UpgradeHandler.StatsChanged:Fire(player)
	return changed
end

export type UpgradeHandler = typeof(UpgradeHandler) & {
	StatCache: { [Player]: { [string]: number } },
}

return UpgradeHandler :: UpgradeHandler
