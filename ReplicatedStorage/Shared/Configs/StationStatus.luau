--!strict
-- Floating status line over busy stations (StationStatusHandler): "Mixing 5s", "Baking 12s",
-- "Needs firewood". Shown while a station has nothing to press, so its progress is readable from
-- across the kitchen instead of only on the prompt of the station last used. Sizes are pixels.

return {
	RefreshInterval = 0.25,
	-- Studs above the top of the station's prompt part.
	Lift = 2.5,
	-- Studs toward the camera (horizontally): prompt parts often sit inside the station's model
	-- (the oven's lies within its brickwork), which would hide a label that does not draw on top.
	-- Labels stay depth-tested so walls of other rooms still cover them.
	Forward = 3,
	MaxDistance = 45,
	Width = 220,
	Height = 34,
	TextSize = 24,
	Face = Color3.fromRGB(255, 255, 255),
	Ink = Color3.fromRGB(58, 32, 22),
	Outline = 2.5,
	-- The label's colour while the station waits on the player (a dead fire) and has no firebox to
	-- carry the icon.
	Alert = Color3.fromRGB(255, 196, 0),
	-- Prompt attribute InteractHandler sets from a view's `Alert` (Shared/BuildingViews/Types), so the
	-- prompt plate leaves an alert to the icon below.
	AlertAttribute = "StatusAlert",

	-- An alert is drawn as an icon in the station's firebox instead of words: a round cream plate
	-- holding the carried firewood model and a small "!" badge, breathing gently. The fire part is the
	-- one OvenView places in the opening (OvenFuel.FirePartPrefix). Sizes are pixels.
	AlertIcon = {
		Size = 72,
		-- Studs toward the camera, so the plate sits in front of the opening instead of inside it.
		Forward = 1.5,
		Plate = Color3.fromRGB(253, 234, 195),
		Edge = Color3.fromRGB(238, 165, 75),
		EdgeThickness = 3,
		-- Share of the plate the firewood model fills.
		ItemScale = 0.8,
		Badge = Color3.fromRGB(226, 66, 52),
		BadgeText = Color3.fromRGB(255, 255, 255),
		BadgeSize = 24,
		-- Badge centre as a share of the plate: its top-right shoulder.
		BadgeAt = Vector2.new(0.86, 0.14),
		PulseScale = 0.07,
		PulseSeconds = 1.3,
	},
}
