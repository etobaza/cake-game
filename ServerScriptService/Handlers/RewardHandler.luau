--!strict
-- Rewards handed out outside the shift loop: promo codes, the daily streak, playtime tiers and the
-- one-off group reward.
--
-- One handler for all of them because they are one job -- grant cash and XP against a rule the
-- server owns -- and because they share the same shape: check what the player is entitled to, write
-- the record that stops it being taken twice, then pay.
--
-- The client sends intent only: a code string, "the daily", or a tier index. Every deadline is
-- computed here from stored timestamps, so a client clock says nothing.
--
-- Playtime is one track per UTC day, saved with the profile. Cloud.Playtime.Seconds holds the time
-- already banked today; Session.Playtime.StartedAt marks where the running stretch began. The server
-- banks the running stretch every SaveInterval, before a claim, and on leave.

--[[ Services ]]--
local GroupService = game:GetService("GroupService")
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
-- Economy reason per reward track; the rest are timed rewards. Skipped tiers are bought with Robux.
local REASONS: { [string]: EconomyHandler.CashReason } = {
	Code = "Gameplay",
	PlaytimeSkip = "IAP",
}

--[[ Types ]]--
type CodeAttempts = {
	-- os.clock when the window opened.
	WindowStart: number,
	Failures: number,
}

--[[ Tables ]]--
local RewardHandler = {
	-- PurchaseHandler because the two Robux buttons on these screens skip a track forward, and the
	-- track is this handler's to move.
	dependencies = { "DataHandler", "EconomyHandler", "PurchaseHandler" },
	priority = 70,
	-- os.clock of each player's last group membership check, so repeated clicks cannot queue web
	-- requests or race a second payout while the first check yields.
	GroupChecks = {} :: { [Player]: number },
	-- Failed code attempts in each player's current window, so codes cannot be guessed by brute force.
	CodeAttempts = {} :: { [Player]: CodeAttempts },
}

--[[ Private Functions ]]--
local function Refuse(player: Player, reason: string): ()
	Bus.Progress.ActionFailed:FireClient(player, reason)
end

-- Membership straight from the web: true or false, or nil when the answer is not certain.
-- IsInGroupAsync can answer from a per-server cache, so a "no" is confirmed against the player's
-- group list before refusing someone who joined during this session; without that list the cached
-- "no" proves nothing, and the check counts as failed.
local function IsGroupMember(player: Player, groupId: number): boolean?
	local cachedOk, cached = pcall(player.IsInGroupAsync, player, groupId)
	if cachedOk and cached == true then
		return true
	end

	local listOk, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if not listOk or typeof(groups) ~= "table" then
		return nil
	end

	for _, group in groups do
		if typeof(group) == "table" and group.Id == groupId then
			return true
		end
	end

	return false
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

	Bus.Progress.ClaimGroup.OnServerEvent:Connect(function(player: Player)
		self:ClaimGroup(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.GroupChecks[player] = nil
		self.CodeAttempts[player] = nil
	end)

	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number)
		self:GrantSkip(player, productId)
	end)

	-- The playtime clock starts when the profile attaches, not when the player joins: before that
	-- there is nowhere to write it.
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:StartClock(player)
	end)

	DataHandler:OnLeaving(function(player: Player)
		self:BankPlaytime(player)
	end)

	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			self:StartClock(player)
		end
	end

	-- Process-lifetime loop: banking bounds what a crashed server can lose.
	task.spawn(function(): ()
		while true do
			task.wait(Rewards.Playtime.SaveInterval)
			for _, player in Players:GetPlayers() do
				self:BankPlaytime(player)
			end
		end
	end)
end

--- Starts a new track when the saved one belongs to an earlier day: no time played, nothing taken.
--- A rollover also restarts the running stretch, so time from before midnight does not carry over.
function RewardHandler.RollPlaytime(_self: RewardHandler, data: DataHandler.PlayerData, now: number): ()
	local record = data.Cloud.Playtime
	local today = Rewards.GetPlaytimeDay(now)
	if record.Day == today then
		return
	end

	record.Day = today
	record.Seconds = 0
	record.Claimed = {}
	if data.Session.Playtime.StartedAt > 0 then
		data.Session.Playtime.StartedAt = now
	end
end

function RewardHandler.StartClock(self: RewardHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local now = workspace:GetServerTimeNow()
	self:RollPlaytime(data, now)
	data.Session.Playtime.StartedAt = now
end

--- Moves the running stretch into today's saved total. Capped at the end of the track, where more
--- time earns nothing.
function RewardHandler.BankPlaytime(self: RewardHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data or data.Session.Playtime.StartedAt <= 0 then
		return
	end

	local now = workspace:GetServerTimeNow()
	self:RollPlaytime(data, now)

	local session = data.Session.Playtime
	local running = now - session.StartedAt
	if running <= 0 then
		return
	end

	local record = data.Cloud.Playtime
	local trackEnd = Rewards.GetTierSeconds(#Rewards.Playtime.Tiers)
	record.Seconds = math.min(record.Seconds + running, trackEnd)
	session.StartedAt = now
end

--- Pays a reward and tells the client what it was, so the toast can name it. `kind` is the reward
--- track (Code, Daily, Playtime, PlaytimeSkip, Group) reported to economy analytics; `source` is only for
--- the player.
function RewardHandler.Pay(
	_self: RewardHandler,
	player: Player,
	reward: Rewards.Reward,
	source: string,
	kind: string
): ()
	if reward.Cash > 0 then
		EconomyHandler:AddCash(player, reward.Cash, REASONS[kind] or "TimedReward", kind)
	end

	if reward.XP > 0 then
		EconomyHandler:AwardXP(player, reward.XP)
	end

	Bus.Progress.RewardGranted:FireClient(player, `{source}: +{reward.Cash} coins, +{reward.XP} XP`)
	Logger:Info(`{player.Name} took {source} for {reward.Cash} coins and {reward.XP} XP`)
end

--- The player's attempt window, reopened once the previous one has run out.
function RewardHandler.GetCodeAttempts(self: RewardHandler, player: Player, now: number): CodeAttempts
	local attempts = self.CodeAttempts[player]
	if attempts and now - attempts.WindowStart < Rewards.CodeAttempts.WindowSeconds then
		return attempts
	end

	local fresh: CodeAttempts = { WindowStart = now, Failures = 0 }
	self.CodeAttempts[player] = fresh
	return fresh
end

--- Refuses a code and counts it against the player's attempt window.
function RewardHandler.FailCode(self: RewardHandler, player: Player, reason: string): boolean
	local attempts = self:GetCodeAttempts(player, os.clock())
	attempts.Failures += 1
	Refuse(player, reason)
	return false
end

function RewardHandler.Redeem(self: RewardHandler, player: Player, code: string): boolean
	-- Only failures count, so a player with several real codes is never held back by them.
	if self:GetCodeAttempts(player, os.clock()).Failures >= Rewards.CodeAttempts.MaxFailures then
		Refuse(player, "code_cooldown")
		return false
	end

	local reward = Rewards.GetCode(code)
	if not reward then
		return self:FailCode(player, "unknown_code")
	end

	local data = DataHandler:GetData(player)
	if not data then
		return false
	end

	-- Stored lowercased so the same code cannot be redeemed again in another casing.
	local stored = string.lower((string.gsub(code, "%s", "")))
	local used = data.Cloud.Rewards.Codes

	if DataList.Contains(used, stored) then
		return self:FailCode(player, "code_used")
	end

	DataList.Append(used, stored)
	self:Pay(player, reward, `Code {stored}`, "Code")

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
	self:Pay(player, reward, `Day {day}`, "Daily")

	return true
end

function RewardHandler.ClaimPlaytime(self: RewardHandler, player: Player, index: number): boolean
	local data = DataHandler:GetData(player)
	local reward = Rewards.GetTier(index)
	if not data or not reward then
		return false
	end

	self:BankPlaytime(player)
	local record = data.Cloud.Playtime

	if record.Seconds < Rewards.GetTierSeconds(index) then
		Refuse(player, "playtime_not_ready")
		return false
	end

	if DataList.Contains(record.Claimed, index) then
		Refuse(player, "playtime_claimed")
		return false
	end

	DataList.Append(record.Claimed, index)
	self:Pay(player, reward, `{index * Rewards.Playtime.Interval // 60} minutes played today`, "Playtime")

	return true
end

--- The one-off reward for joining the group. The client only asks; membership is checked here, and
--- the claim flag is written before paying so a second request cannot pay twice.
function RewardHandler.ClaimGroup(self: RewardHandler, player: Player): boolean
	local data = DataHandler:GetData(player)
	if not data then
		return false
	end

	if data.Cloud.Rewards.GroupClaimed then
		Refuse(player, "group_claimed")
		return false
	end

	local now = os.clock()
	local lastCheck = self.GroupChecks[player]
	if lastCheck and now - lastCheck < Rewards.Group.CheckCooldown then
		return false
	end
	self.GroupChecks[player] = now

	local member = IsGroupMember(player, Rewards.Group.GroupId)

	-- The lookup yields: the player may have left, or the profile may have been replaced meanwhile.
	if player.Parent ~= Players or DataHandler:GetData(player) ~= data or data.Cloud.Rewards.GroupClaimed then
		return false
	end

	if member == nil then
		Refuse(player, "group_check_failed")
		return false
	end

	if not member then
		Refuse(player, "group_not_member")
		return false
	end

	data.Cloud.Rewards.GroupClaimed = true
	self:Pay(player, Rewards.Group.Reward, "Group reward", "Group")

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
		-- Today's track: a skip bought just after midnight pays the new day's tiers.
		self:RollPlaytime(data, workspace:GetServerTimeNow())
		local record = data.Cloud.Playtime

		for index = 1, #Rewards.Playtime.Tiers do
			local reward = Rewards.GetTier(index)
			if reward and not DataList.Contains(record.Claimed, index) then
				DataList.Append(record.Claimed, index)
				self:Pay(player, reward, `Tier {index}`, "PlaytimeSkip")
			end
		end

		Logger:Info(`{player.Name} skipped the playtime track`)
	end
end

export type RewardHandler = typeof(RewardHandler)

return RewardHandler :: RewardHandler
