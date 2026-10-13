--!strict
local MixerInteraction = {
	-- Space between the bowl centre and the player's root, toward the kitchen aisle.
	StandDistance = 3.2,
	-- The authored ingredient card is sized in studs, so it shrinks with the screen like the world
	-- does. On a screen shorter than this it keeps the pixel size it has on one this tall, so its
	-- title stays legible and its chips stay large enough to tap on phones.
	CardMinViewportHeight = 720,
}

return MixerInteraction
