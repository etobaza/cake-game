--!strict
-- Lemon Cake's firewood lasts 90 seconds (180 upgraded), with a fresh variation per refill.
return {
	DurationVariation = 10,
	EffectAsset = "OvenFire",
	-- The fire clone in an oven's opening is named this plus the oven's building id (OvenView); the
	-- client finds it there to pin the out-of-firewood icon (StationStatusHandler).
	FirePartPrefix = "Fire_",
}
