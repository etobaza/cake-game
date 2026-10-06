--!strict
-- Order cards adapt Lemon Cake with remaining patience; durations remain in CustomerTypes.

return {
	-- Shorter than Lemon Cake's 10-20 seconds: a seated guest staring at the menu is dead time.
	ChooseMinSeconds = 4,
	ChooseMaxSeconds = 8,
	FirstGuestChooseSeconds = 1,
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
	},
	TooltipWidth = 280,
	TooltipHeight = 76,
	TooltipGap = 8,
	TooltipMinTextSize = 14,
	TooltipMaxTextSize = 18,
}
