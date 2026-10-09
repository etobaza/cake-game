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
	-- The label's colour while the station waits on the player (a dead fire).
	Alert = Color3.fromRGB(255, 196, 0),
	AlertWords = { "firewood" } :: { string },
}
