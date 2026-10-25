--!strict
-- The paid 2x coin boost: every purchase adds Seconds of doubled gameplay coins. The time runs only
-- while the player is in the game (banked in Cloud.CashBoostSeconds on leave, resumed on join), and
-- buying again while it runs adds to what is left. Robux purchases and admin grants are never doubled.

--[[ Tables ]]--
local CashBoost = {
	-- Registries/Products entry sold by the HUD button.
	Product = "boost_cash_2x",
	Seconds = 15 * 60,
	Multiplier = 2,
	-- Banked to the profile this often while it runs, so a crash loses at most this much.
	SaveInterval = 30,

	-- HUD button: the authored side Shop button's icon and label only (its tile and input cue are
	-- dropped). Shared/UI/HudLayout places it in the top-right corner, beside the quests on phones.
	Button = {
		Template = { "HUD", "SideBtns", "Shop" },
		Name = "CashBoost",
		Icon = "rbxassetid://109504819496800",
		PulseScale = 0.06,
		PulsePeriod = 1.4,
		IdleText = "2x Cash",
		ActiveColor = Color3.fromRGB(120, 255, 120),
	},
}

--- Coin multiplier the boost adds at `now`, from the session's end time.
function CashBoost.GetMultiplier(endsAt: number?, now: number): number
	return if typeof(endsAt) == "number" and endsAt > now then CashBoost.Multiplier else 1
end

return CashBoost
