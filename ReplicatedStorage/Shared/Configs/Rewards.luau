--!strict
-- Rewards handed out outside the shift loop: promo codes, the daily streak and playtime tiers.
--
-- Sizes are read off the screens they fill: the daily screen was drawn with seven tiles (a row of
-- four over a row of three) and the playtime screen with fifteen (three rows of five), so the tables
-- below are exactly that long. Adding a tile in StarterGui means adding a row here, and nothing else.
--
-- The numbers are scaled to the shift: dishes sell for 75-400 coins (coffee 800) plus tips, and an
-- early Lemon Cake-paced shift (about 4.5 minutes with the evening) admits 10-12 guests and earns
-- roughly 2 000-3 500 coins and 40-50 XP, about 30 000-40 000 coins an hour. The whole upgrade tree
-- costs 513 275 coins. Free rewards stay a bonus on top of that pace:
--   * the 7-day streak pays 38 500 coins in total, from one shift to five shifts a day;
--   * a full day's playtime track (75 minutes of play) adds 12 200 coins, under half an hour's income;
--   * the welcome code and the group reward together buy the first few cheap upgrades.

--[[ Tables ]]--
local Rewards = {
	-- Art for the last daily and playtime tile, so the biggest reward stands out from the coin tiles.
	FinalIcon = "rbxassetid://104023635875665",
	-- Every other tile grows with its cash: the first step whose Max covers the amount wins. These are
	-- the store's cash-pack images, from a handful of coins up to a coin-filled chest.
	CashIcons = {
		{ Max = 500, Icon = "rbxassetid://96216232687018" },
		{ Max = 1000, Icon = "rbxassetid://114454707057271" },
		{ Max = 2500, Icon = "rbxassetid://71273978435843" },
		{ Max = 6000, Icon = "rbxassetid://127494963095045" },
		{ Max = math.huge, Icon = "rbxassetid://110097182380053" },
	} :: { { Max: number, Icon: string } },

	-- Promo codes, lowercased. The player types one in and it can be redeemed once per account.
	-- Real campaign codes go here; `welcome` is the one that ships. 2 500 coins buys the first two
	-- Display Counter levels.
	Codes = {
		welcome = { Cash = 2500, XP = 10 },
	} :: { [string]: Reward },
	-- Per-player cap on failed code attempts (unknown or already used): after MaxFailures in one
	-- window, further codes are refused until WindowSeconds have passed since the window opened.
	CodeAttempts = {
		MaxFailures = 5,
		WindowSeconds = 60,
	},

	-- One-off reward for joining the experience's Roblox group, paid once per account: about half a
	-- shift.
	Group = {
		GroupId = 712136202,
		Reward = { Cash = 4000, XP = 15 } :: Reward,
		-- Seconds between membership checks per player: each check is a web request.
		CheckCooldown = 5,
	},

	Daily = {
		-- A claim is allowed once every DailyCooldown, and the streak breaks after DailyGrace.
		Cooldown = 20 * 60 * 60,
		Grace = 48 * 60 * 60,

		Days = {
			{ Cash = 2000, XP = 5 },
			{ Cash = 2500, XP = 8 },
			{ Cash = 3500, XP = 10 },
			{ Cash = 4500, XP = 12 },
			{ Cash = 6000, XP = 15 },
			{ Cash = 8000, XP = 20 },
			{ Cash = 12000, XP = 30 },
		} :: { Reward },
	},

	-- One track per real (UTC) day, saved with the profile: time played in every session that day
	-- adds up, rejoining keeps it, and the next day starts a fresh track.
	Playtime = {
		-- Seconds of play between tiers. The whole track is an hour and a quarter.
		Interval = 5 * 60,
		-- Length of a playtime day. Day numbers count these from the Unix epoch, so days turn at UTC
		-- midnight for every server alike.
		DayLength = 24 * 60 * 60,
		-- How often the server moves the running session's time into the saved total. Leaving saves it
		-- at once; this only bounds the loss from a crashed server.
		SaveInterval = 30,

		-- 12 200 coins and 80 XP (about one shift of XP) in total.
		Tiers = {
			{ Cash = 400, XP = 3 },
			{ Cash = 400, XP = 3 },
			{ Cash = 500, XP = 3 },
			{ Cash = 500, XP = 4 },
			{ Cash = 600, XP = 4 },
			{ Cash = 600, XP = 4 },
			{ Cash = 700, XP = 5 },
			{ Cash = 700, XP = 5 },
			{ Cash = 800, XP = 5 },
			{ Cash = 800, XP = 6 },
			{ Cash = 900, XP = 6 },
			{ Cash = 1000, XP = 6 },
			{ Cash = 1100, XP = 7 },
			{ Cash = 1200, XP = 7 },
			{ Cash = 2000, XP = 12 },
		} :: { Reward },
	},
}

--[[ Types ]]--
export type Reward = {
	Cash: number,
	XP: number,
}

--[[ Handling ]]--
--- Tile art for a reward; the last tile of a track always shows the chest.
function Rewards.GetIcon(reward: Reward, isFinal: boolean): string
	if isFinal then
		return Rewards.FinalIcon
	end
	for _, step in Rewards.CashIcons do
		if reward.Cash <= step.Max then
			return step.Icon
		end
	end
	return Rewards.FinalIcon
end

--- The reward for day `index` of the streak; nil past the last tile.
function Rewards.GetDay(index: number): Reward?
	return Rewards.Daily.Days[index]
end

--- The reward for playtime tier `index`; nil past the last tile.
function Rewards.GetTier(index: number): Reward?
	return Rewards.Playtime.Tiers[index]
end

--- Seconds played in a day before tier `index` can be claimed.
function Rewards.GetTierSeconds(index: number): number
	return index * Rewards.Playtime.Interval
end

--- The playtime day a server time (workspace:GetServerTimeNow) falls in.
function Rewards.GetPlaytimeDay(serverTime: number): number
	return serverTime // Rewards.Playtime.DayLength
end

--- Seconds played today: the saved total for `day`, plus the running session since `startedAt`.
--- A saved total from an earlier day counts as nothing; the server rolls it over on its next save.
function Rewards.GetPlayedSeconds(day: number, savedSeconds: number, startedAt: number, now: number): number
	local saved = if day == Rewards.GetPlaytimeDay(now) then savedSeconds else 0
	local running = if startedAt > 0 then math.max(now - startedAt, 0) else 0
	return saved + running
end

--- The reward for a code, matched case-insensitively and ignoring the spaces around it.
function Rewards.GetCode(code: string): Reward?
	return Rewards.Codes[string.lower((string.gsub(code, "%s", "")))]
end

return Rewards
