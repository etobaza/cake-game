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
	-- A ready guest whistles again at this interval until the order is taken; long enough not to nag.
	ReadyWhistleSeconds = 20,
	-- The speech bubble and the order card both beat at this interval while the guest is ready.
	ReadyPulseSeconds = 1.1,
	Slots = 4,
	ProgressSteps = 100,
	RefreshInterval = 0.25,
	PonderInterval = 0.5,
	-- Logical sizes drawn at the HUD's screen density (Shared/UI/HudLayout), capped at MaxScale.
	Layout = {
		CardWidth = 124,
		Height = 180,
		LabelWidth = 64,
		Edge = 16,
		MaxScale = 1.4,
		CardGap = 6,
		ContentPadding = 5,
		HotbarGap = 12,
	},
	-- Card punches (Animate.Pop start scale): a new guest's card grows in, a placed order kicks.
	Pop = {
		Appear = 0.55,
		Placed = 1.25,
	},
	-- Speech bubble over each of the owner's seated guests (GuestOrderHandler). Sizes are layout pixels
	-- drawn at a constant world size (Theme.WorldScale), so the bubble shrinks with distance like its guest.
	Bubble = {
		-- States that show a bubble; Arriving and Eating guests have their own cues.
		States = { Queued = true, Choosing = true, Waiting = true } :: { [string]: boolean },
		-- The bubble's world size relative to Theme.WorldScale, so orders read from across the room.
		WorldScale = 1.3,
		-- Captions never wrap (the renderer would re-wrap them as the bubble scales), so the width fits
		-- the longest dish name (Blueberry Cheesecake, 184 pixels at TextSize) with room for the font
		-- snapping a UIScale causes.
		Width = 216,
		Padding = 6,
		IconSize = 44,
		IconGap = 4,
		MaxIcons = 3,
		CaptionHeight = 50,
		-- One caption line per dish.
		LineHeight = 25,
		TextSize = 21,
		PonderSize = 36,
		BarHeight = 10,
		CornerRadius = 10,
		StrokeThickness = 2,
		TailSize = 12,
		BadgeSize = 26,
		BadgeTextSize = 18,
		-- Studs above the head centre; the bubble grows upward from there. MinHeight clears ordinary
		-- hats; a taller accessory lifts it to HatMargin above the accessory's top, up to MaxHeight.
		MinHeight = 1.7,
		HatMargin = 0.3,
		MaxHeight = 4,
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
		ReadyPulseFrom = 1.12,
		-- New bubble words type out with the guest's NpcText blip (BattlesOfEmpires' NPC voice):
		-- seconds per letter, the minimum time before the blip may restart, and pitch spread.
		Voice = { CharSeconds = 0.03, Restart = 0.07, Spread = 0.05 },
	},
	-- Status line drawn over the top of each order card (OrderHandler/Card): what the guest needs
	-- next, coloured by urgency. Heights and slot placement are shares of the card; text sizes are
	-- logical pixels at the cards' density. A two-line status (several dishes) takes the Multiple
	-- values and pushes the authored slot (number and dish art) further down.
	CardStatus = {
		Height = 0.32,
		MultipleHeight = 0.45,
		SlotY = 0.64,
		SlotHeight = 0.5,
		MultipleSlotY = 0.7,
		MultipleSlotHeight = 0.4,
		-- Above the authored card art.
		ZIndex = 10,
		MinTextSize = 14,
		MaxTextSize = 18,
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
		ReadyPulseFrom = 1.08,
	},
	-- Pages the order panel stays up for: the recipe pick is where the player decides what to cook.
	StaysOverPages = { RecipeToCook = true } :: { [string]: boolean },
	-- The recipe pick marks dishes guests are waiting for and lists them first.
	WaitingBadge = {
		TextSize = 18,
		-- The face runs from ColorTop down to Color.
		ColorTop = Color3.fromRGB(255, 176, 72),
		Color = Color3.fromRGB(240, 100, 24),
		TextColor = Color3.fromRGB(255, 255, 255),
		-- The border, the lettering's outline and the plate under the face share the cocoa ink.
		EdgeColor = Color3.fromRGB(95, 51, 51),
		Edge = 2.5,
		TextOutline = 1.5,
		Padding = 10,
		Height = 26,
		-- How far the plate shows below the face.
		Depth = 3,
		Inset = Vector2.new(8, 6),
		PulseSeconds = 0.9,
		PulseScale = 1.06,
		-- Plate, face and lettering stack upward from this ZIndex, above the row's art.
		ZIndex = 10,
	},
	-- Logical pixels at the cards' density, like the status text.
	TooltipWidth = 300,
	TooltipHeight = 88,
	TooltipGap = 8,
	-- Pixels kept between the tooltip and the HUD's side edges.
	TooltipMargin = 8,
	TooltipMinTextSize = 18,
	TooltipMaxTextSize = 22,
	-- How long a tapped card's name stays up on touch screens.
	TooltipTouchSeconds = 2.5,
}
