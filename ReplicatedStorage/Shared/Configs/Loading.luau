--!strict
-- The join loading screen: ReplicatedFirst/Loading drives the authored ReplicatedFirst.LoadingScreen.

return {
	-- Instances whose art is cached before the screen lifts, as a service name then child names: only
	-- the interface the first view shows, so a first join on a new device is not a full download.
	Preload = {
		{ "StarterGui", "MainGui" },
	},
	-- Cached after the screen lifts, so guests, dishes and effects are usually ready before they first
	-- appear. Configs/Sounds effects are added to these; music streams on its own.
	Background = {
		{ "ReplicatedStorage", "Assets", "Models" },
		{ "ReplicatedStorage", "Assets", "VFX" },
		{ "ReplicatedStorage", "Assets", "Prompt" },
	},
	-- The bar's share for the interface art; the rest fills once the character stands in its bakery.
	AssetShare = 0.9,
	-- Once the character stands in its bakery, the screen waits at most this long for interface art
	-- still downloading; anything left pops in on its own.
	AssetGraceSeconds = 3,
	-- How quickly the drawn bar catches up with the real progress, per second.
	BarCatchUp = 6,
	-- A fast join still shows the screen this long, so it does not flash.
	MinSeconds = 1.5,
	-- The full bar stays on screen this long before the fade.
	FullHoldSeconds = 0.35,
	FadeSeconds = 0.5,
	-- Skip appears for slow connections and lifts the screen at once.
	SkipAfterSeconds = 6,
	TipSeconds = 5,
	-- The cake bobs and sways on its badge while loading.
	BobPixels = 8,
	BobSpeed = 2.4,
	SwayDegrees = 4,
	SwaySpeed = 1.7,
	Status = {
		Assets = "Preheating the ovens...",
		Bakery = "Opening your bakery...",
	},
	Tips = {
		"Serve guests quickly: happy guests leave bigger tips.",
		"Serve good orders in a row to build a streak for bonus tips.",
		"A more varied menu earns bigger tips.",
		"Sweep up spills with the broom to keep your bakery clean.",
		"Keep an eye on the oven: food left inside too long burns.",
		"Critics tip big but have little patience. Watch for their banner!",
		"Keep the oven stocked with firewood, or it stops baking.",
		"Every friend playing with you boosts your earnings.",
		"Upgrades unlock new ingredients and faster stations.",
		"Claim free playtime rewards from the Rewards button.",
		"Hold Shift to run, or tap the Run button on touch screens.",
	},
}
