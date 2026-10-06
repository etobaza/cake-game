--!strict
-- Success feedback tuning: how a sold dish, a level up and other accepted actions look and sound on
-- the owner's screen. Presentation only; the server decides every amount, grade and streak.

--[[ Modules ]]--
local Sounds = require(script.Parent.Sounds)

--[[ Types ]]--
export type Grade = "Perfect" | "Great" | "Late" | "Sold"

export type GradeStyle = {
	-- Caption above the amount.
	Text: string,
	-- The caption's vertical gradient (top to bottom) and outline.
	Top: Color3,
	Bottom: Color3,
	Stroke: Color3,
	-- Burst at the dish from `Configs/VFX`, fired by the server for every nearby player.
	Effect: string?,
	-- Layered over the register for the best service.
	Flourish: Sounds.SoundName?,
	RegisterVolume: number,
	-- Popup size relative to `Popup.Size`.
	Scale: number,
}

--[[ Tables ]]--
-- Server reaction (`VFXRules.Reaction`) to sale grade. Window purchases always read "Sold".
local gradeByReaction: { [string]: Grade } = {
	Happy = "Perfect",
	Singing = "Great",
	Angry = "Late",
}

local grades: { [Grade]: GradeStyle } = {
	Perfect = {
		Text = "PERFECT!",
		Top = Color3.fromRGB(255, 246, 130),
		Bottom = Color3.fromRGB(255, 150, 30),
		Stroke = Color3.fromRGB(92, 40, 8),
		Effect = "ServePerfect",
		Flourish = "Sparkle",
		RegisterVolume = 1,
		Scale = 1.1,
	},
	Great = {
		Text = "GREAT!",
		Top = Color3.fromRGB(196, 255, 140),
		Bottom = Color3.fromRGB(40, 196, 92),
		Stroke = Color3.fromRGB(18, 70, 32),
		Effect = "ServeGreat",
		RegisterVolume = 0.9,
		Scale = 1,
	},
	Late = {
		Text = "LATE...",
		Top = Color3.fromRGB(255, 205, 190),
		Bottom = Color3.fromRGB(214, 92, 82),
		Stroke = Color3.fromRGB(78, 24, 24),
		Effect = "ServeLate",
		RegisterVolume = 0.6,
		Scale = 0.85,
	},
	Sold = {
		Text = "SOLD!",
		Top = Color3.fromRGB(176, 236, 255),
		Bottom = Color3.fromRGB(64, 150, 255),
		Stroke = Color3.fromRGB(16, 46, 100),
		Effect = "ServeSold",
		RegisterVolume = 0.75,
		Scale = 0.9,
	},
}

return {
	-- Above pages (2-5) and the status toast; below tutorial guidance (50) and hints (55).
	DisplayOrder = 45,
	GradeByReaction = gradeByReaction,
	Grades = grades,
	-- Window shoppers carry their pastry this many studs below the head; their sale bursts there.
	CarriedDrop = 1.4,

	-- Pixel sizes below are designed at this viewport height and scale with the screen, clamped.
	ReferenceHeight = 900,
	MinScale = 0.6,
	MaxScale = 1.2,

	-- The floating "+24$" over the guest. A pixel-sized billboard stays readable at any distance.
	Popup = {
		Width = 320,
		Offset = Vector3.new(0, 1.9, 0),
		-- Used when the guest's head has not streamed in: studs above the sale point.
		FallbackLift = 3,
		Rise = 2.4,
		Lifetime = 1.8,
		FadeFrom = 1.2,
		MaxDistance = 150,
		PopSeconds = 0.38,
		-- Caption, amount and streak appear one after another.
		Stagger = 0.07,
		Tilt = -6,
		GradeTextSize = 34,
		AmountTextSize = 50,
		StreakTextSize = 22,
		CoinSize = 44,
		StrokeThickness = 3,
		AmountTop = Color3.fromRGB(255, 255, 255),
		AmountBottom = Color3.fromRGB(255, 220, 110),
		AmountStroke = Color3.fromRGB(74, 36, 8),
	},

	-- Server-counted table-service streak: Perfect and Great continue it, Late and walk-outs end it,
	-- and every good sale tips extra for the run before it (`Economy.GetStreakTipBonus`).
	Streak = {
		-- The sale popup's streak line, from this length: streak and the tip bonus this sale earned.
		ShowFrom = 2,
		Format = "x%d STREAK  +%d%% TIPS",
		FormatNoBonus = "x%d STREAK",
		Top = Color3.fromRGB(255, 214, 92),
		Bottom = Color3.fromRGB(255, 84, 48),
		Stroke = Color3.fromRGB(86, 18, 8),
		-- The register and coin ticks climb with the streak.
		PitchStep = 0.03,
		PitchMax = 1.3,
		-- Beating the all-time best is announced once per run, from this length.
		RecordFrom = 3,
		RecordText = "NEW RECORD!",
		RecordTop = Color3.fromRGB(255, 236, 255),
		RecordBottom = Color3.fromRGB(196, 92, 255),
		RecordStroke = Color3.fromRGB(58, 14, 88),
		-- A run shorter than this ends quietly.
		LoseFrom = 2,
		LostText = "STREAK LOST",
		-- Milestones get the banner and a fire burst; past the last one, every Nth sale does.
		Milestones = { 3, 5, 10, 15, 20, 25, 30 },
		MilestoneEvery = 10,
		-- The banner title is the highest entry at or below the streak.
		Titles = {
			{ From = 3, Text = "HOT STREAK!" },
			{ From = 5, Text = "ON FIRE!" },
			{ From = 10, Text = "BLAZING!" },
			{ From = 15, Text = "UNSTOPPABLE!" },
			{ From = 20, Text = "LEGENDARY!" },
		},
		Flame = "rbxassetid://132800636580675",
		Puff = "rbxassetid://112634016917346",
		Glow = "rbxassetid://115581071626835",
		-- The flame burns hotter as the run grows: glow colour, count gradient and size.
		Tiers = {
			{
				From = 1,
				Glow = Color3.fromRGB(255, 150, 40),
				Top = Color3.fromRGB(255, 250, 200),
				Bottom = Color3.fromRGB(255, 170, 40),
				Scale = 1,
			},
			{
				From = 5,
				Glow = Color3.fromRGB(255, 70, 30),
				Top = Color3.fromRGB(255, 236, 150),
				Bottom = Color3.fromRGB(255, 80, 30),
				Scale = 1.12,
			},
			{
				From = 10,
				Glow = Color3.fromRGB(255, 60, 200),
				Top = Color3.fromRGB(255, 220, 255),
				Bottom = Color3.fromRGB(255, 70, 160),
				Scale = 1.25,
			},
		},
		-- Fire-coloured screen confetti for milestones.
		Colors = {
			Color3.fromRGB(255, 70, 40),
			Color3.fromRGB(255, 150, 30),
			Color3.fromRGB(255, 215, 60),
		},
		Meter = {
			-- Pixels right of the HUD coin.
			Gap = 10,
			FlameSize = 66,
			CountTextSize = 44,
			BonusTextSize = 20,
			BonusFormat = "+%d%% TIPS",
			StrokeThickness = 3,
			Stroke = Color3.fromRGB(86, 18, 8),
			BonusTop = Color3.fromRGB(220, 255, 170),
			BonusBottom = Color3.fromRGB(90, 220, 90),
			-- Embers rise from the flame; the interval shrinks as the run grows.
			EmberSeconds = 0.5,
			LoseSeconds = 1.3,
		},
		Banner = {
			-- Below the clock and the status toast.
			Anchor = Vector2.new(0.5, 0.32),
			Seconds = 1.7,
			ExitSeconds = 0.3,
			-- Lettering only, in fire colours, without a plate behind it.
			Width = 600,
			TitleHeight = 84,
			TitleTop = Color3.fromRGB(255, 248, 180),
			TitleBottom = Color3.fromRGB(255, 96, 30),
			TitleStroke = Color3.fromRGB(96, 18, 8),
			FlameSize = 96,
			TitleTextSize = 58,
			SubtitleTextSize = 24,
			-- White to beige: fire colours would melt into the warm wood behind the run line.
			SubtitleTop = Color3.fromRGB(255, 255, 255),
			SubtitleBottom = Color3.fromRGB(255, 230, 186),
			SubtitleFormat = "x%d STREAK  +%d%% TIPS",
			Confetti = 30,
			-- World burst around the player's character (`Configs/VFX`).
			Effect = "StreakBurst",
		},
	},

	-- Coins burst from the sale point and fly into the HUD balance, which counts up as they land.
	Coins = {
		Image = "rbxassetid://100304091769166",
		-- count = clamp(round(Base + amount * PerCoin), Min, Max); dish prices run 0.75-8.
		Base = 2,
		PerCoin = 1.2,
		Min = 3,
		Max = 12,
		Size = 36,
		-- Pixels and seconds: a short ballistic pop, then the homing flight.
		LaunchSpeed = NumberRange.new(240, 460),
		LaunchSeconds = NumberRange.new(0.16, 0.26),
		Gravity = 1300,
		FlightSeconds = NumberRange.new(0.38, 0.56),
		Stagger = 0.04,
		-- Seconds of the pop's velocity that bend the homing curve outward.
		Arc = 0.3,
		Spin = NumberRange.new(-260, 260),
		MaxActive = 48,
		TickPitch = 0.95,
		TickPitchStep = 0.045,
		TickPitchMax = 1.55,
		-- A sale releases its held balance after this long even if a coin never lands.
		HoldSeconds = 4,
		IconPopFrom = 1.35,
		-- Off-screen sales launch from the screen edge in their direction, this far from the centre
		-- (fraction of the shorter screen side).
		EdgeInset = 0.42,
	},

	LevelUp = {
		Star = "rbxassetid://86577432302115",
		Rays = "rbxassetid://80513051336918",
		RaysColor = Color3.fromRGB(255, 210, 90),
		NumberStroke = Color3.fromRGB(92, 40, 8),
		-- The title is lettering only, gold like the star, without a plate behind it.
		Title = "LEVEL UP!",
		TitleTop = Color3.fromRGB(255, 252, 200),
		TitleBottom = Color3.fromRGB(255, 170, 30),
		TitleStroke = Color3.fromRGB(92, 40, 8),
		TitleBox = Vector2.new(460, 72),
		UnlockSingle = "New recipe: %s",
		UnlockMany = "New recipes: %s",
		-- Banner centre as a fraction of the screen.
		Anchor = Vector2.new(0.5, 0.34),
		StarSize = 200,
		RaysSize = 560,
		RaysSpeed = 28,
		Seconds = 3.2,
		ExitSeconds = 0.35,
		NumberTextSize = 78,
		TitleTextSize = 60,
		SubtitleTextSize = 26,
		Confetti = 48,
		-- World burst around the player's character (`Configs/VFX`).
		Effect = "LevelUp",
	},

	-- Screen-space confetti and sparkles shared by the level up and purchase bursts.
	Confetti = {
		Images = { "rbxassetid://137101016360901", "rbxassetid://79682178388502" },
		Colors = {
			Color3.fromRGB(255, 86, 120),
			Color3.fromRGB(255, 205, 60),
			Color3.fromRGB(80, 200, 255),
			Color3.fromRGB(120, 230, 90),
			Color3.fromRGB(190, 130, 255),
		},
		Size = NumberRange.new(22, 38),
		Speed = NumberRange.new(380, 820),
		Gravity = 900,
		Drag = 1.6,
		Lifetime = NumberRange.new(1.4, 2.2),
		Spin = NumberRange.new(-420, 420),
	},
	Sparkle = {
		Image = "rbxassetid://17062454177",
		Color = Color3.fromRGB(255, 236, 140),
		Size = NumberRange.new(18, 34),
		Speed = NumberRange.new(120, 260),
		Lifetime = NumberRange.new(0.35, 0.6),
	},
	-- A bought upgrade node bursts in place.
	Celebrate = {
		Sparkles = 10,
		Confetti = 14,
	},
	MaxSparks = 160,
}
