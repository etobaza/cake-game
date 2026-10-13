--!strict
-- Admin abuse live event: who appears, what they say, and every gameplay number of the event.
-- Everything an event needs to be tuned lives here; the handlers only read it.
--
-- Cast avatars are built from the UserIds at runtime, so outfit changes show up on their own, and
-- display names are read at runtime too: dialogue text never names a cast member.

--[[ Types ]]--
export type CastMember = {
	UserId: number,
	-- Shown under the display name on the HUD banner.
	Role: string,
}

export type Line = {
	-- Cast id from `Cast`.
	Speaker: string,
	Text: string,
	-- Seconds after the event start.
	At: number,
}

export type Script = {
	-- Admin panel label.
	Name: string,
	-- Seconds the event lasts: giants, golden guests and cupcake rain all end together.
	Duration: number,
	-- Sorted by `At` when read. The giants on stage are the speakers, in order of their first line.
	Lines: { Line },
}

export type ScheduleEntry = {
	Script: string,
	-- UTC start time.
	Hour: number,
	Minute: number,
	-- 1 = Sunday … 7 = Saturday (os.date "wday"); nil means every day.
	Weekdays: { number }?,
}

--[[ Tables ]]--
local AdminAbuse = {
	Cast = {
		hyper = { UserId = 301599546, Role = "Studio co-owner" },
		inc = { UserId = 1657140835, Role = "Studio owner" },
		funset = { UserId = 11124027070, Role = "Scripter" },
		martin = { UserId = 33640830, Role = "Game designer" },
	} :: { [string]: CastMember },

	-- Script the Cmdr command starts when no id is given.
	DefaultScript = "all_hands",

	Scripts = {
		all_hands = {
			Name = "All hands",
			Duration = 300,
			Lines = {
				{
					At = 0,
					Speaker = "inc",
					Text = "Hello, bakers! The studio is taking over this server for a few minutes!",
				},
				{
					At = 6,
					Speaker = "hyper",
					Text = "We've been watching your kitchens. Some of you bake faster than our ovens!",
				},
				{ At = 12, Speaker = "martin", Text = "Golden guests are on their way. They pay five times more!" },
				{
					At = 18,
					Speaker = "funset",
					Text = "And I wrote a tiny script that makes it rain cupcakes. Grab them!",
				},
				{ At = 24, Speaker = "inc", Text = "Serve fast and pick up every cupcake you see." },
				{ At = 30, Speaker = "hyper", Text = "Admin abuse is live! Let's go!" },
				{ At = 120, Speaker = "martin", Text = "Halfway there. Keep those ovens hot!" },
				{ At = 126, Speaker = "funset", Text = "No bugs so far. Probably." },
				{ At = 240, Speaker = "inc", Text = "One more minute! Grab every cupcake you can!" },
				{ At = 285, Speaker = "hyper", Text = "That's all for today. Thanks for baking with us!" },
				{ At = 291, Speaker = "martin", Text = "See you at the next admin abuse!" },
			},
		},
		owner_and_scripter = {
			Name = "Owner and scripter",
			Duration = 300,
			Lines = {
				{ At = 0, Speaker = "inc", Text = "Is the cupcake machine ready?" },
				{ At = 5, Speaker = "funset", Text = "Ready. Pressing the button now..." },
				{ At = 10, Speaker = "funset", Text = "Oops. I think I pressed it too hard." },
				{ At = 15, Speaker = "inc", Text = "It's raining cupcakes everywhere! Grab them, bakers!" },
				{ At = 21, Speaker = "inc", Text = "And golden guests pay five times more while we're here." },
				{ At = 150, Speaker = "funset", Text = "Should I turn it off?" },
				{ At = 155, Speaker = "inc", Text = "Not yet! Let them bake a little longer." },
				{ At = 280, Speaker = "funset", Text = "Okay, the machine is out of cupcakes." },
				{ At = 286, Speaker = "inc", Text = "Thanks for playing, everyone! See you next time!" },
			},
		},
		hyper_solo = {
			Name = "Hyper solo",
			Duration = 300,
			Lines = {
				{ At = 0, Speaker = "hyper", Text = "Hey, everyone! Time for a little admin abuse." },
				{ At = 6, Speaker = "hyper", Text = "Look up! Cupcakes are falling from the sky." },
				{ At = 12, Speaker = "hyper", Text = "Golden guests pay five times more for the next few minutes." },
				{ At = 150, Speaker = "hyper", Text = "Still baking? Good. Keep going!" },
				{ At = 285, Speaker = "hyper", Text = "That's it from me. Thanks for playing!" },
			},
		},
	} :: { [string]: Script },

	-- Where the giants stand: on the cliff over the tunnel at the south end of the street, outside
	-- the playable map, facing up the road so they tower over it. World coordinates.
	Stage = {
		-- Middle of the line of giants. Each giant stands on whatever ground is under its slot;
		-- the Y value is only the fallback when there is none.
		Origin = Vector3.new(116, 0, -490),
		-- Point the giants face.
		LookAt = Vector3.new(116, 0, -126),
		-- Studs between neighbouring giants, after scaling.
		Spacing = 150,
		-- Model:ScaleTo factor; a default R15 avatar is about 5.5 studs tall, so 40 is about
		-- 220 studs, towering over the 76-stud bakeries and the 86-stud cliff.
		Scale = 40,
	},

	-- Dialogue presentation.
	Speech = {
		-- A line stays up until the next one starts, but never longer than this.
		LineSeconds = 7,
		-- Speech bubble over a giant's head, in studs per unit of Stage.Scale, so it grows with the
		-- giants (6 x 1.6 is 240 x 64 studs at scale 40).
		BubbleSize = Vector2.new(6, 1.6),
		-- Gap above the top of the head, in studs per unit of Stage.Scale; clears tall hats.
		BubbleOffset = 1,
		-- Tag and colour of the mirrored system chat line.
		ChatTag = "LIVE",
		ChatColor = Color3.fromRGB(255, 196, 64),
		-- Bubble look; the outline uses Hud.Accent.
		BubbleColor = Color3.fromRGB(255, 255, 255),
		BubbleTextColor = Color3.fromRGB(40, 26, 22),
		BubbleStrokeThickness = 3,
		-- Text inset on each side, as a fraction of the bubble: this much of the width and twice this
		-- much of the height.
		BubbleTextPadding = 0.06,
	},

	-- HUD banner with the speaker's headshot.
	Hud = {
		Title = "ADMIN ABUSE",
		StartingText = "Starting in %d...",
		LiveText = "Golden guests x5 • Cupcake rain • %s left",
		-- Below the day sign at the top of the HUD.
		Position = UDim2.new(0.5, 0, 0, 120),
		Width = 560,
		DisplayOrder = 30,
		Accent = Color3.fromRGB(255, 196, 64),
		-- Card look, in pixels where it is a size.
		CardColor = Color3.fromRGB(40, 26, 22),
		CardTransparency = 0.15,
		CornerRadius = 14,
		StrokeThickness = 2,
		Padding = 10,
		HeadshotSize = 64,
		-- Colour of the role line under the speaker's name.
		RoleColor = Color3.fromRGB(230, 214, 196),
		TextSizes = {
			Status = 16,
			Name = 20,
			Role = 14,
			Line = 18,
		},
		-- Scale the card pops from when a new line appears.
		LinePopFrom = 0.92,
	},

	-- Golden event guests. Their look, patience and payout multiplier are the customer type
	-- `TypeId` in Configs/Registries/CustomerTypes; this table only says how often they come.
	Guests = {
		TypeId = "event_guest",
		-- Chance that a seated arrival during the event is a golden guest instead.
		Chance = 0.35,
		-- Golden guests in one bakery at the same time.
		MaxActive = 1,
	},

	-- Cupcakes falling around every player; the owner walks into one to collect it.
	Rain = {
		-- Path under ReplicatedStorage.Assets.Models.
		Model = { "Cake", "CarrotCupcake" },
		ModelScale = 2,
		-- Coins per cupcake, paid as gameplay income (pass and friend multipliers apply).
		Coins = 2,
		-- Cupcakes one player can collect during one event.
		MaxPerPlayer = 40,
		-- Uncollected cupcakes around one player at the same time.
		MaxActive = 6,
		-- Seconds between drops for each player.
		Interval = 3,
		-- Ring around the player where a cupcake lands, in studs.
		MinRadius = 6,
		MaxRadius = 20,
		-- Studs above the landing point where the fall starts.
		DropHeight = 40,
		FallSeconds = 1.4,
		-- Studs from the character to the cupcake to collect it.
		PickupRadius = 5,
		-- An uncollected cupcake disappears after this many seconds.
		LifeSeconds = 30,
		-- Analytics item id of the cupcake income.
		AnalyticsItem = "LiveEventCupcake",
		-- Client idle motion of a landed cupcake: spin in radians per second; the bob's angular speed
		-- in radians per second, and half its travel in studs.
		SpinSpeed = 2,
		BobSpeed = 3,
		BobHeight = 0.4,
	},

	-- Cross-server relay through MessagingService. Delivery is best effort, so the server that
	-- started an event re-broadcasts it; every server resolves the dialogue from this config.
	Relay = {
		Topic = "AdminAbuseLiveEvent",
		-- Seconds between the start command and the first line, so every server catches up.
		LeadSeconds = 4,
		RebroadcastSeconds = 30,
		-- A relayed start may lie at most LeadSeconds plus this far in the future (server clocks
		-- drift apart a little); later or already-finished start times are dropped as forged or stale.
		StartSlackSeconds = 10,
		-- Seconds between attempts while subscribing to the topic fails.
		SubscribeRetrySeconds = 30,
	},

	-- Automatic starts. Every server computes the same slots from the UTC clock, so a scheduled
	-- event needs no messaging at all. Admins can still start or stop events by hand.
	Schedule = {
		Enabled = false,
		CheckSeconds = 5,
		Entries = {
			{ Script = "all_hands", Hour = 18, Minute = 0, Weekdays = { 7 } },
		} :: { ScheduleEntry },
	},
}

return AdminAbuse
