--!strict
-- Uploaded sound assets and their playback tuning. World sounds are positional; local feedback
-- sounds (pages, hands, sales, level ups) play unpositioned on the client.

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
	| "Mixing"
	| "BoilingCoffee"
	| "Fridge"
	| "Cart"
	| "PickingFruit"
	| "CashRegister"
	| "Coin"
	| "Sparkle"
	| "LevelUp"
	| "StationReady"
	| "OrderUp"
	| "Purchase"
	| "Reward"
	| "Pop"
	| "StreakMilestone"
	| "NewRecord"
	| "FireWhoosh"

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
	Mixing = { Id = "rbxassetid://108542822843617", Volume = 0.5, Looped = true, MaxDistance = 40 },
	BoilingCoffee = { Id = "rbxassetid://138677402895041", Volume = 0.5, Looped = true, MaxDistance = 40 },
	Fridge = { Id = "rbxassetid://107114224608756", Volume = 0.6 },
	Cart = { Id = "rbxassetid://125102916550683", Volume = 0.6 },
	PickingFruit = { Id = "rbxassetid://91529448118673", Volume = 0.6 },
	-- Success feedback: free Creator Store effects, chosen for an immediate attack (under 0.05 s of
	-- leading silence) so they land on the frame the action is accepted. Replace freely.
	CashRegister = { Id = "rbxassetid://18444218362", Volume = 0.45 },
	-- Played once per coin landing in the HUD balance, with a rising pitch.
	Coin = { Id = "rbxassetid://120543211338337", Volume = 0.22 },
	Sparkle = { Id = "rbxassetid://2609981431", Volume = 0.35 },
	LevelUp = { Id = "rbxassetid://128460880879263", Volume = 0.55 },
	StationReady = { Id = "rbxassetid://110253665387820", Volume = 0.6, MaxDistance = 45 },
	OrderUp = { Id = "rbxassetid://135165335432475", Volume = 0.45, MaxDistance = 45 },
	Purchase = { Id = "rbxassetid://136211732441165", Volume = 0.45 },
	Reward = { Id = "rbxassetid://134821092416328", Volume = 0.5 },
	Pop = { Id = "rbxassetid://119697580657161", Volume = 0.35 },
	StreakMilestone = { Id = "rbxassetid://98922486018976", Volume = 0.5 },
	NewRecord = { Id = "rbxassetid://103918660379424", Volume = 0.5 },
	-- Flares at streak milestones; played slowed and low, it is the flame snuffing out.
	FireWhoosh = { Id = "rbxassetid://100453569471578", Volume = 0.4 },
}

-- Loops while a station mixes or cooks, keyed by building kind.
local stationWork: { [string]: SoundName } = {
	Mixer = "Mixing",
	Coffee = "BoilingCoffee",
}

-- Plays once as a batch goes into or comes out of the station, keyed by building kind.
local stationDoor: { [string]: SoundName } = {
	Freezer = "Fridge",
}

-- Rings once when a batch finishes, keyed by building kind, so the player knows to collect it.
local stationReady: { [string]: SoundName } = {
	Mixer = "StationReady",
	Oven = "StationReady",
	Freezer = "StationReady",
	Coffee = "StationReady",
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
	StationWork = stationWork,
	StationDoor = stationDoor,
	StationReady = stationReady,
}
