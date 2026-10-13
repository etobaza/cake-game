--!strict
-- Local purchase presentation. Paths resolve beneath the owner's bakery, with authored whitespace trimmed.
local Sounds = require(script.Parent.Sounds)
export type TargetSpec = {
	Paths: { string }?,
	LevelPaths: { string }?,
	Source: string?,
	Character: boolean?,
	Fade: boolean?,
	FocusHeight: number?,
	FocusPaths: { string }?,
	FocusSize: Vector3?,
	Benefit: string,
	-- Purchase level -> copy that replaces Benefit for that one level.
	LevelBenefits: { [number]: string }?,
}

return {
	DisplayOrder = 60,
	MaxQueued = 3,
	QueueLifetime = 8,
	ReplicationWait = 1.5,
	ReplicationSettle = 0.12,
	ArmLifetime = 3,
	ApproachSeconds = 0.55,
	HoldSeconds = 1.65,
	ReturnSeconds = 0.4,
	FadeSeconds = 0.55,
	-- Share of the approach that passes before new geometry starts fading in.
	FadeStartShare = 0.45,
	-- Seconds between re-scans of masked/fading geometry for late-replicated parts. A scan walks every
	-- target descendant, so it runs once per phase start and then on this interval, not every frame.
	CaptureInterval = 0.1,
	AppearanceAttribute = "UpgradeRevealAlpha",
	Sound = "Purchase" :: Sounds.SoundName,
	Flourish = "Sparkle" :: Sounds.SoundName,
	FlourishPitch = 1.05,
	VFX = { Template = { "Cleaning", "Stars" }, Count = 8, Size = 0.55, Speed = NumberRange.new(2, 5) },
	Camera = {
		FieldOfView = 58,
		Radius = 0.65,
		WallMargin = 0.35,
		MinDistance = 5,
		MaxDistance = 64,
		FramePadding = 1.12,
		ScreenMargin = 0.06,
		CardGap = 0.03,
		-- Screen-height range (from the top) where the receipt's upper edge may limit the framing.
		MinCardEdge = 0.35,
		MaxCardEdge = 0.9,
		-- Narrowest aspect ratio used for the horizontal frustum on very tall viewports.
		MinAspect = 0.3,
		-- Candidate score penalties: per 180 degrees of yaw away from the front, per unit of elevation.
		AngleWeight = 0.12,
		ElevationWeight = 0.08,
		Elevations = { 0.2, 0.5, 0.8 },
		OrbitDegrees = 7,
		Angles = { 0, 35, -35, 70, -70, 110, -110, 180 },
	},
	Card = {
		Width = 530,
		Height = 140,
		MinHeight = 160,
		NarrowHeight = 160,
		Bottom = 30,
		-- Bottom offset never drops below this many pixels, whatever the density.
		MinBottom = 18,
		Margin = 16,
		-- Pixel sizes scale with viewport height / DensityHeight, clamped to this range.
		DensityHeight = 900,
		MinDensity = 0.85,
		MaxDensity = 1.2,
		-- Below this width the receipt switches to the compact layout.
		NarrowWidth = 400,
		IconSize = 84,
		NarrowIconSize = 64,
		TitleSize = 27,
		MinTitleSize = 16,
		BenefitSize = 18,
		MinBenefitSize = 16,
		TagSize = 13,
		SkipWidth = 156,
		SkipHeight = 46,
		SkipTextSize = 18,
		SkipTransparency = 0.05,
		Corner = 20,
		SkipCorner = 14,
		EdgeThickness = 3,
		-- Receipt layout offsets, in pixels.
		Padding = 14,
		RightPadding = 16,
		-- The text column starts this far right of the icon's width.
		TextColumnGap = 32,
		IconLift = 3,
		TagTop = 16,
		TagHeight = 18,
		TagSkipGap = 40,
		TitleTop = 55,
		TitleHeight = 32,
		BenefitTop = 91,
		BenefitBottom = 22,
		SkipInset = Vector2.new(12, 8),
		TrackInset = 10,
		TrackSidePadding = 16,
		TrackHeight = 3,
		TrackTransparency = 0.75,
		-- Arrival scale pop: EnterScale -> 1 with this OutBack overshoot.
		EnterScale = 0.94,
		EnterOvershoot = 0.4,
		EnterSeconds = 0.35,
		ExitSeconds = 0.2,
		-- First sparkle burst, offset from the receipt's top-left corner.
		TwinkleOffset = Vector2.new(45, 20),
		TwinkleCount = 5,
		Cream = Color3.fromRGB(255, 242, 215),
		Shine = Color3.fromRGB(255, 250, 235),
		Edge = Color3.fromRGB(151, 89, 55),
		Accent = Color3.fromRGB(235, 169, 67),
		Veil = Color3.fromRGB(61, 35, 27),
		-- Upgrade category -> tag text. An unknown category falls back to its upper-cased name.
		CategoryLabels = { Cafe = "CAFE", Kitchen = "KITCHEN", Garden = "GREENHOUSE" } :: { [string]: string },
		FallbackCategory = "BAKERY",
		FallbackBenefit = "Your bakery just got better.",
	},
	Hud = { SizeMultiplier = 1.14 },
	-- New geometry fades; stat purchases spotlight a real related object without making it disappear.
	Targets = {
		cafe_display = {
			LevelPaths = {
				"1ndFloor.Cafe.Upgrades.DisplayCounter.Upgrade1",
				"1ndFloor.Cafe.Upgrades.DisplayCounter.Upgrade2",
				"1ndFloor.Cafe.Upgrades.DisplayCounter.Upgrade3",
				"1ndFloor.Cafe.Upgrades.DisplayCounter.Upgrade4",
				"1ndFloor.Cafe.Upgrades.DisplayCounter.Upgrade5",
			},
			Fade = true,
			Benefit = "One more pastry on display. More room to sell.",
		},
		cafe_window = {
			Paths = { "1ndFloor.Cafe.Upgrades.KitchenWindow.Upgrade" },
			Fade = true,
			Benefit = "Pass a pastry from the kitchen to the café.",
		},
		cafe_catcafe = {
			LevelPaths = { "1ndFloor.Cafe.Upgrades.CatCafe.Upgrade1", "1ndFloor.Cafe.Upgrades.CatCafe.Upgrade2" },
			Fade = true,
			Benefit = "Happier guests. Bigger tips.",
		},
		cafe_coffee = {
			Paths = { "1ndFloor.Cafe.Upgrades.CoffeeMachine.Upgrade" },
			Fade = true,
			Benefit = "Coffee is ready to join your menu.",
		},
		cafe_tables = {
			Paths = { "1ndFloor.Cafe.Upgrades.TwoSeatsTable.Upgrade" },
			Fade = true,
			Benefit = "Two new seats for hungry guests.",
		},
		cafe_assistant = {
			Paths = { "1ndFloor.Cafe.Upgrades.KitchenWindow.Upgrade" },
			Benefit = "A helping hand. Choose tomorrow's job in Next Menu.",
		},
		kitchen_counter = {
			Paths = {
				"1ndFloor.Kitchen.Decoration.KitchenCounter.Circle",
				"1ndFloor.Kitchen.Decoration.KitchenCounter.Mixer",
			},
			Benefit = "Your mixer now works 25% faster.",
		},
		kitchen_fuel = {
			Paths = { "1ndFloor.Kitchen.Decoration.Oven" },
			FocusHeight = 8,
			Benefit = "Each log now burns twice as long.",
		},
		kitchen_oven = {
			LevelPaths = {
				"1ndFloor.Kitchen.Upgrades.OvenUpgrade.Upgrade2",
				"1ndFloor.Kitchen.Upgrades.OvenUpgrade.Upgrade1",
			},
			Fade = true,
			FocusHeight = 8,
			Benefit = "Another oven. Bake two batches at once.",
			LevelBenefits = { [2] = "Your third oven. Bake three batches at once." },
		},
		kitchen_chickens = { Source = "animal_2", Fade = true, Benefit = "Fresh eggs, right in your kitchen." },
		kitchen_cow = { Source = "animal_1", Fade = true, Benefit = "Fresh milk for your cream recipes." },
		kitchen_freezer = {
			Paths = { "1ndFloor.Kitchen.Upgrades.Freezer.Upgrade" },
			Fade = true,
			Benefit = "Frozen desserts are now on the menu.",
		},
		kitchen_burnguard = {
			Paths = { "1ndFloor.Kitchen.Decoration.Oven" },
			FocusHeight = 8,
			Benefit = "60 seconds to collect ready food before it burns.",
		},
		kitchen_sprint = { Character = true, Benefit = "Lighter shoes. Sprint faster between jobs." },
		kitchen_brush = { Source = "animal_2", Benefit = "Brushed animals stay clean until tomorrow." },
		garden_cocoa = { Source = "tree_4", Fade = true, Benefit = "Water your cocoa tree to grow fresh cocoa." },
		garden_cherry = { Source = "tree_2", Fade = true, Benefit = "Fresh cherries from your own tree." },
		garden_strawberry = { Source = "plot_1", Fade = true, Benefit = "Your first patch of fresh strawberries." },
		garden_blueberry = { Source = "plot_2", Fade = true, Benefit = "Fresh blueberries for more recipes." },
		garden_water = {
			Paths = { "1ndFloor.Garden.Decoration.Sink", "1ndFloor.Garden.Upgrades.CrystalWater.Upgrade" },
			Benefit = "Watered plants stay moist twice as long.",
		},
		garden_grape = { Source = "plot_3", Fade = true, Benefit = "Grow your own grapes in the greenhouse." },
		garden_cart = {
			Paths = { "1ndFloor.Kitchen.Upgrades.RailCart.Upgrade" },
			FocusPaths = { "1ndFloor.Kitchen.Upgrades.RailCart.Upgrade.Model" },
			Fade = true,
			Benefit = "Send produce to the kitchen. Four delivery spaces.",
		},
		garden_carrot = { Source = "plot_4", Fade = true, Benefit = "Fresh carrots for your next bake." },
		garden_sprinkler = {
			Paths = { "1ndFloor.Garden.Upgrades.Sprinkler.Upgrade" },
			-- The ceiling pipe mesh spans the whole greenhouse; feature its central junction.
			FocusSize = Vector3.new(12, 8, 12),
			Fade = true,
			Benefit = "Your plants and trees water themselves.",
		},
		garden_apple = { Source = "tree_1", Fade = true, Benefit = "Fresh apples from your own tree." },
		garden_beehive = { Source = "animal_3", Fade = true, Benefit = "Fresh honey. Plants grow 25% faster." },
		garden_lemon = { Source = "tree_3", Fade = true, Benefit = "Fresh lemons. Your greenhouse is complete!" },
	} :: { [string]: TargetSpec },
}
