--!strict
-- Background music (MusicHandler): the Increates Cake Game soundtrack, played on every client in
-- order and looped. Like Lemon Cake's BP_Music, each track fades in and out over FadeSeconds and
-- the next one starts after the previous has faded away.

export type Track = {
	Name: string,
	Id: string,
}

return {
	Tracks = {
		{ Name = "Cake ST1", Id = "rbxassetid://113240304099751" },
		{ Name = "Cake ST2", Id = "rbxassetid://92379705505873" },
		{ Name = "Cake ST3", Id = "rbxassetid://77419305000636" },
	} :: { Track },
	-- Full volume of a track between its fades; quiet enough to sit under the game sounds.
	Volume = 0.3,
	-- Lemon Cake fades its music in and out over five seconds.
	FadeSeconds = 5,
	-- A track that has not loaded after this long is skipped.
	LoadTimeoutSeconds = 15,
	-- SoundService group every track plays through, for a future music volume setting.
	GroupName = "Music",
}
