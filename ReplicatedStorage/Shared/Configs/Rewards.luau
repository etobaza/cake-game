--!strict
-- Rewards handed out outside the shift loop: promo codes, the daily streak and playtime tiers.
--
-- Sizes are read off the screens they fill: the daily screen was drawn with seven tiles (a row of
-- four over a row of three) and the playtime screen with fifteen (three rows of five), so the tables
-- below are exactly that long. Adding a tile in StarterGui means adding a row here, and nothing else.
--
-- The numbers are scaled to the shift: a dish sells for 14-30 and the first upgrades cost 120-250, so
-- a day's login is worth about one cheap upgrade and a full playtime run about four.

--[[ Tables ]]--
local Rewards = {
	-- Art for the last daily and playtime tile, so the biggest reward stands out from the coin tiles.
	FinalIcon = "rbxassetid://104023635875665",
	-- Every other tile grows with its cash: the first step whose Max covers the amount wins. These are
	-- the store's cash-pack images, from a handful of coins up to a coin-filled chest.
	CashIcons = {
		{ Max = 100, Icon = "rbxassetid://96216232687018" },
		{ Max = 200, Icon = "rbxassetid://114454707057271" },
		{ Max = 350, Icon = "rbxassetid://71273978435843" },
		{ Max = 500, Icon = "rbxassetid://127494963095045" },
		{ Max = math.huge, Icon = "rbxassetid://110097182380053" },
	} :: { { Max: number, Icon: string } },

	-- Promo codes, lowercased. The player types one in and it can be redeemed once per account.
	-- Real campaign codes go here; `welcome` is the one that ships.
	Codes = {
		welcome = { Cash = 250, XP = 10 },
	} :: { [string]: Reward },

	Daily = {
		-- A claim is allowed once every DailyCooldown, and the streak breaks after DailyGrace.
		Cooldown = 20 * 60 * 60,
		Grace = 48 * 60 * 60,

		Days = {
			{ Cash = 100, XP = 5 },
			{ Cash = 150, XP = 10 },
			{ Cash = 250, XP = 10 },
			{ Cash = 350, XP = 15 },
			{ Cash = 500, XP = 20 },
			{ Cash = 700, XP = 30 },
			{ Cash = 1000, XP = 40 },
		} :: { Reward },
	},

	Playtime = {
		-- Seconds of one session between tiers. The whole track is an hour and a quarter.
		Interval = 5 * 60,

		Tiers = {
			{ Cash = 50, XP = 2 },
			{ Cash = 75, XP = 3 },
			{ Cash = 100, XP = 4 },
			{ Cash = 125, XP = 5 },
			{ Cash = 150, XP = 6 },
			{ Cash = 175, XP = 7 },
			{ Cash = 200, XP = 8 },
			{ Cash = 250, XP = 9 },
			{ Cash = 300, XP = 10 },
			{ Cash = 350, XP = 11 },
			{ Cash = 400, XP = 12 },
			{ Cash = 450, XP = 13 },
			{ Cash = 500, XP = 14 },
			{ Cash = 700, XP = 18 },
			{ Cash = 1000, XP = 25 },
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

--- Seconds of a session before tier `index` can be claimed.
function Rewards.GetTierSeconds(index: number): number
	return index * Rewards.Playtime.Interval
end

--- The reward for a code, matched case-insensitively and ignoring the spaces around it.
function Rewards.GetCode(code: string): Reward?
	return Rewards.Codes[string.lower((string.gsub(code, "%s", "")))]
end

return Rewards
