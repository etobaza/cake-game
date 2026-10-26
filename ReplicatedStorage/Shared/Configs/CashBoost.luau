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
	-- dropped). Shared/UI/HudLayout places it in the top-right corner, left of the player list on desktops.
	Button = {
		Template = { "HUD", "SideBtns", "Shop" },
		Name = "CashBoost",
		Icon = "rbxassetid://109504819496800",
		IdleText = "2x Cash",
		ActiveColor = Color3.fromRGB(120, 255, 120),
		-- While the offer is up, the Store's shine rays turn behind the coin.
		Rays = "rbxassetid://80513051336918",
		-- Ray side as a share of the button's height, turn speed in degrees per second.
		RaysSize = 1.6,
		RaysSpeed = 35,
		RaysColor = Color3.fromRGB(255, 200, 40),
		RaysTransparency = 0,
		-- Idle: the coin rocks gently and hops every HopPeriod seconds, rising HopHeight of the button's
		-- height and growing by HopScale at the top of the hop.
		TiltDegrees = 5,
		TiltPeriod = 2.2,
		HopPeriod = 2.6,
		HopSeconds = 0.5,
		HopHeight = 0.12,
		HopScale = 0.12,
		-- A tap pops the button and shakes the coin, decaying over TapSeconds; the rays spin faster.
		TapSeconds = 0.6,
		TapDegrees = 16,
		TapRaysBoost = 5,
	},
}

--- Coin multiplier the boost adds at `now`, from the session's end time.
function CashBoost.GetMultiplier(endsAt: number?, now: number): number
	return if typeof(endsAt) == "number" and endsAt > now then CashBoost.Multiplier else 1
end

return CashBoost
