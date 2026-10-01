--!strict
-- Uploaded sound assets and their playback tuning. World sounds are positional; local feedback
-- sounds (pages, hands) play unpositioned on the client.

export type SoundName =
	"AnimalWash"
	| "OvenFire"
	| "Broom"
	| "BroomSuccess"
	| "Get"
	| "Put"
	| "UiOpen"
	| "UiClose"
	| "WaiterWhistle"
	| "GuestHappy"
	| "GuestSad"

export type Definition = {
	Id: string,
	Volume: number,
	Looped: boolean?,
	-- Positional range in studs; defaults below apply when omitted.
	MinDistance: number?,
	MaxDistance: number?,
}

-- Floor sweeping plays Broom immediately and BroomSuccess once the one-second sweep clip ends.
local sounds: { [SoundName]: Definition } = {
	AnimalWash = { Id = "rbxassetid://74656423388646", Volume = 0.6 },
	OvenFire = { Id = "rbxassetid://73082904486477", Volume = 0.35, Looped = true, MaxDistance = 35 },
	Broom = { Id = "rbxassetid://74111077255725", Volume = 0.7 },
	BroomSuccess = { Id = "rbxassetid://104455064249115", Volume = 0.5 },
	Get = { Id = "rbxassetid://74035026465975", Volume = 0.5 },
	Put = { Id = "rbxassetid://136151656235659", Volume = 0.5 },
	UiOpen = { Id = "rbxassetid://73574670346128", Volume = 0.5 },
	UiClose = { Id = "rbxassetid://97979022375379", Volume = 0.5 },
	WaiterWhistle = { Id = "rbxassetid://74906107284599", Volume = 0.6 },
	GuestHappy = { Id = "rbxassetid://94829056430888", Volume = 0.6 },
	GuestSad = { Id = "rbxassetid://107122932837050", Volume = 0.6 },
}

-- A served guest's reaction (`VFXRules.Reaction`) picks its voice; on-time and quick service sound happy.
local reactions: { [string]: SoundName } = {
	Happy = "GuestHappy",
	Singing = "GuestHappy",
	Angry = "GuestSad",
}

return {
	MinDistance = 10,
	MaxDistance = 60,
	-- One-shots are destroyed after this many seconds even if `Ended` never fires (servers do not
	-- simulate playback). Must exceed the longest one-shot clip.
	Lifetime = 6,
	Sounds = sounds,
	Reactions = reactions,
}
