--!strict
-- Order cards adapt Lemon Cake with remaining patience; durations remain in CustomerTypes.

return {
	-- Shorter than Lemon Cake's 10-20 seconds: a seated guest staring at the menu is dead time.
	ChooseMinSeconds = 4,
	ChooseMaxSeconds = 8,
	FirstGuestChooseSeconds = 1,
	-- After choosing, a seated guest is ready to order and waits for the player's Take order.
	-- Patience starts at that moment, so leaving a guest unattended costs time. A guest nobody
	-- serves (AFK, gamepad, a busy kitchen) orders on their own after this long; 0 restores the old
	-- automatic order the moment choosing ends.
	TakeOrderFallbackSeconds = 25,
	-- A ready guest whistles again at this interval until the order is taken.
	ReadyWhistleSeconds = 8,
	Slots = 4,
	ProgressSteps = 100,
	RefreshInterval = 0.25,
	PonderInterval = 0.5,
	Layout = {
		Compact = { CardWidth = 64, Height = 110, LabelWidth = 52, Edge = 8 },
		Wide = { CardWidth = 80, Height = 140, LabelWidth = 64, Edge = 16 },
		MaxScale = 1.25,
		CardGap = 6,
		ContentPadding = 5,
		HotbarGap = 12,
	},
	-- Card punches (Animate.Pop start scale): a new guest's card grows in, a placed order kicks.
	Pop = {
		Appear = 0.55,
		Placed = 1.25,
	},
	-- Speech bubble over each of the owner's seated guests (GuestOrderHandler). Sizes are pixels.
	Bubble = {
		-- States that show a bubble; Arriving and Eating guests have their own cues.
		States = { Queued = true, Choosing = true, Waiting = true } :: { [string]: boolean },
		Width = 124,
		Padding = 6,
		IconSize = 44,
		IconGap = 4,
		MaxIcons = 3,
		CaptionHeight = 18,
		TextSize = 14,
		PonderSize = 36,
		BarHeight = 10,
		CornerRadius = 10,
		StrokeThickness = 2,
		TailSize = 12,
		BadgeSize = 22,
		BadgeTextSize = 13,
		-- Above the head centre; the bubble grows upward from here, clear of hats.
		Offset = Vector3.new(0, 1.7, 0),
		MaxDistance = 70,
		-- Below this share of patience the bar turns red and the bubble starts to wobble.
		LowPatience = 0.3,
		WobbleSeconds = 1.2,
		WobbleDegrees = 6,
		LowGradient = ColorSequence.new(Color3.fromRGB(255, 120, 90), Color3.fromRGB(220, 30, 30)),
		QueuedText = "Need a table!",
		-- Ready to order: a large "!" in place of the choosing dots, a call and a steady pulse.
		ReadyText = "Take my order!",
		ReadyMarkColor = Color3.fromRGB(255, 170, 0),
		ReadyPulseSeconds = 1.1,
		ReadyPulseFrom = 1.12,
		-- New bubble words type out with the guest's NpcText blip (BattlesOfEmpires' NPC voice):
		-- seconds per letter, the minimum time before the blip may restart, and pitch spread.
		Voice = { CharSeconds = 0.03, Restart = 0.07, Spread = 0.05 },
	},
	-- Status line drawn over the top of each order card (OrderHandler/Card): what the guest needs
	-- next, coloured by urgency. Height is a share of the card; text sizes are pixels.
	CardStatus = {
		Height = 0.24,
		MinTextSize = 9,
		MaxTextSize = 15,
		StrokeThickness = 1.5,
		StrokeColor = Color3.fromRGB(58, 32, 22),
		Colors = {
			Choosing = Color3.fromRGB(255, 255, 255),
			Ready = Color3.fromRGB(255, 196, 0),
			Cook = Color3.fromRGB(255, 255, 255),
			Serve = Color3.fromRGB(110, 255, 90),
			Eating = Color3.fromRGB(200, 200, 200),
			Low = Color3.fromRGB(255, 90, 70),
		} :: { [string]: Color3 },
		-- Card art tint while the guest's patience is below Bubble.LowPatience.
		LowTint = Color3.fromRGB(255, 150, 140),
		-- Eating guests keep their card, dimmed, until they leave the table.
		EatingTransparency = 0.35,
		ReadyPulseSeconds = 1.1,
		ReadyPulseFrom = 1.08,
	},
	-- Pages the order panel stays up for: the recipe pick is where the player decides what to cook.
	StaysOverPages = { RecipeToCook = true } :: { [string]: boolean },
	-- The recipe pick marks dishes guests are waiting for and lists them first.
	WaitingBadge = {
		TextSize = 18,
		Color = Color3.fromRGB(255, 120, 40),
		TextColor = Color3.fromRGB(255, 255, 255),
		Padding = 6,
		Height = 24,
	},
	TooltipWidth = 280,
	TooltipHeight = 76,
	TooltipGap = 8,
	TooltipMinTextSize = 14,
	TooltipMaxTextSize = 18,
}
