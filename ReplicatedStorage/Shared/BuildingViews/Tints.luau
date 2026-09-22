-- Colours a building takes on while it is in a state worth noticing from across the room.
-- One shared meaning per colour: the player learns four colours instead of one per station kind.
-- A view returning no tint leaves the building its own colour from the registry.

--[[ Tables ]]--
local Tints = {
	-- Something of the player's is running here and needs no attention yet.
	Busy = Color3.fromRGB(240, 168, 72),
	-- Finished and waiting to be picked up.
	Ready = Color3.fromRGB(126, 208, 116),
	-- Ruined or dirty: it costs the player something until it is dealt with.
	Bad = Color3.fromRGB(94, 82, 76),
	-- Occupied by a guest.
	Guest = Color3.fromRGB(232, 172, 196),
	-- Growing in the garden.
	Growing = Color3.fromRGB(120, 158, 84),
}

return Tints
