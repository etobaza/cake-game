--!strict
-- Rewards handed out outside the shift loop: promo codes, the daily streak and playtime tiers.
--
-- One handler for the three of them because they are one job -- grant cash and XP against a rule the
-- server owns -- and because they share the same shape: check what the player is entitled to, write
-- the record that stops it being taken twice, then pay.
--
-- The client sends intent only: a code string, "the daily", or a tier index. Every deadline is
-- computed here from stored timestamps, so a client clock says nothing.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local EconomyHandler = require(ServerScriptService.Handlers.EconomyHandler)
local LoggerUtil = require(_Libs.Logger)
local Products = require(_Configs.Registries.Products)
local PurchaseHandler = require(ServerScriptService.Handlers.PurchaseHandler)
local Rewards = require(_Configs.Rewards)
local Sanitize = require(_Shared.Sanitize)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "RewardHandler" })

--[[ Constants ]]--
local MAX_CODE_LENGTH = 32

--[[ Tables ]]--
local RewardHandler = {
	-- PurchaseHandler because the two Robux buttons on these screens skip a track forward, and the
	-- track is this handler's to move.
	dependencies = { "DataHandler", "EconomyHandler", "PurchaseHandler" },
	priority = 70,
}

--[[ Private Functions ]]--
local function Refuse(player: Player, reason: string): ()
	Bus.Progress.ActionFailed:FireClient(player, reason)
end

--[[ Handling ]]--
function RewardHandler.OnStart(self: RewardHandler): ()
	Bus.Progress.RedeemCode.OnServerEvent:Connect(function(player: Player, rawCode: any)
		local code = Sanitize.Id(rawCode)
		if code and #code <= MAX_CODE_LENGTH then
			self:Redeem(player, code)
		end
	end)

	Bus.Progress.ClaimDaily.OnServerEvent:Connect(function(player: Player)
		self:ClaimDaily(player)
	end)

	Bus.Progress.ClaimPlaytime.OnServerEvent:Connect(function(player: Player, rawIndex: any)
		local index = Sanitize.Index(rawIndex, #Rewards.Playtime.Tiers)
		if index then
			self:ClaimPlaytime(player, index)
		end
	end)

	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number)
		self:GrantSkip(player, productId)
	end)

	-- The playtime clock starts when the profile attaches, not when the player joins: before that
	-- there is nowhere to write it.
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:StartClock(player)
	end)

	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			self:StartClock(player)
		end
	end
end

function RewardHandler.StartClock(_self: RewardHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	data.Session.Playtime.StartedAt = workspace:GetServerTimeNow()
end

--- Pays a reward and tells the client what it was, so the toast can name it.
function RewardHandler.Pay(_self: RewardHandler, player: Player, reward: Rewards.Reward, source: string): ()
	if reward.Cash > 0 then
		EconomyHandler:AddCash(player, reward.Cash)
	end

	if reward.XP > 0 then
		EconomyHandler:AwardXP(player, reward.XP)
	end

	Bus.Progress.RewardGranted:FireClient(player, `{source}: +{reward.Cash} coins, +{reward.XP} XP`)
	Logger:Info(`{player.Name} took {source} for {reward.Cash} coins and {reward.XP} XP`)
end

function RewardHandler.Redeem(self: RewardHandler, player: Player, code: string): boolean
	local reward = Rewards.GetCode(code)
	if not reward then
		Refuse(player, "unknown_code")
		return false
	end

	local data = DataHandler:GetData(player)
	if not data then
		return false
	end

	-- Stored lowercased so the same code cannot be redeemed again in another casing.
	local stored = string.lower((string.gsub(code, "%s", "")))
	local used = data.Cloud.Rewards.Codes

	if DataList.Contains(used, stored) then
		Refuse(player, "code_used")
		return false
	end

	DataList.Append(used, stored)
	self:Pay(player, reward, `Code {stored}`)

	return true
end

--- The next day of the streak, or nil while it is still cooling down.
--- A gap longer than Grace drops the streak back to its first day instead of refusing.
function RewardHandler.NextDay(_self: RewardHandler, player: Player): number?
	local data = DataHandler:GetData(player)
	if not data then
		return nil
	end

	local record = data.Cloud.Rewards
	local since = os.time() - record.ClaimedAt

	if record.ClaimedAt > 0 and since < Rewards.Daily.Cooldown then
		return nil
	end

	if record.ClaimedAt == 0 or since > Rewards.Daily.Grace then
		return 1
	end

	return record.Day + 1
end

function RewardHandler.ClaimDaily(self: RewardHandler, player: Player): boolean
	local data = DataHandler:GetData(player)
	local day = self:NextDay(player)
	if not data or not day then
		Refuse(player, "daily_not_ready")
		return false
	end

	local reward = Rewards.GetDay(day)
	if not reward then
		Refuse(player, "daily_done")
		return false
	end

	data.Cloud.Rewards.Day = day
	data.Cloud.Rewards.ClaimedAt = os.time()
	self:Pay(player, reward, `Day {day}`)

	return true
end

function RewardHandler.ClaimPlaytime(self: RewardHandler, player: Player, index: number): boolean
	local data = DataHandler:GetData(player)
	local reward = Rewards.GetTier(index)
	if not data or not reward then
		return false
	end

	local record = data.Session.Playtime
	local elapsed = workspace:GetServerTimeNow() - record.StartedAt

	if elapsed < Rewards.GetTierSeconds(index) then
		Refuse(player, "playtime_not_ready")
		return false
	end

	if DataList.Contains(record.Claimed, index) then
		Refuse(player, "playtime_claimed")
		return false
	end

	DataList.Append(record.Claimed, index)
	self:Pay(player, reward, `{index * Rewards.Playtime.Interval // 60} minutes played`)

	return true
end

--- The two Robux buttons on these screens: one clears the wait on the daily, the other pays out
--- every playtime tier that has not been taken yet.
function RewardHandler.GrantSkip(self: RewardHandler, player: Player, productId: number): ()
	local entry = Products:GetByProductId(productId)
	local meta = entry and entry.meta
	local data = DataHandler:GetData(player)
	if not entry or not meta or not data then
		return
	end

	if meta.grant == "SkipDaily" then
		-- Backdating the claim is the whole skip: the next day becomes claimable at once, and the
		-- streak stays inside its grace window.
		data.Cloud.Rewards.ClaimedAt = os.time() - Rewards.Daily.Cooldown
		Logger:Info(`{player.Name} skipped the wait on the daily`)
		return
	end

	if meta.grant == "SkipPlaytime" then
		local record = data.Session.Playtime

		for index = 1, #Rewards.Playtime.Tiers do
			local reward = Rewards.GetTier(index)
			if reward and not DataList.Contains(record.Claimed, index) then
				DataList.Append(record.Claimed, index)
				self:Pay(player, reward, `Tier {index}`)
			end
		end

		Logger:Info(`{player.Name} skipped the playtime track`)
	end
end

export type RewardHandler = typeof(RewardHandler)

return RewardHandler :: RewardHandler
