--!strict
-- Order cards adapt Lemon Cake with remaining patience; durations remain in CustomerTypes.

return {
	ChooseMinSeconds = 10,
	ChooseMaxSeconds = 20,
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
	TooltipWidth = 280,
	TooltipHeight = 76,
	TooltipGap = 8,
	TooltipMinTextSize = 14,
	TooltipMaxTextSize = 18,
}
