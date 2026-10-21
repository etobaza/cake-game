--!strict
-- Controller cues (Shared/UI/InputCue): the glyph badge on a button and the gamepad button that
-- presses it. Only a controller shows them; the glyph art (Xbox or PlayStation) comes from
-- UserInputService.

return {
	-- D-pad Up stays with TopbarPlus, which lifts gamepad focus onto the topbar (Daily Rewards, Codes).
	Keys = {
		Upgrades = Enum.KeyCode.DPadRight,
		Shop = Enum.KeyCode.DPadDown,
		Rewards = Enum.KeyCode.DPadLeft,
		-- Tab rows inside pages: upgrade categories, the evening Report and Menu.
		PreviousTab = Enum.KeyCode.ButtonL1,
		NextTab = Enum.KeyCode.ButtonR1,
		-- The open page's main button: Purchase in the upgrade tree, Next Day in the evening.
		PageAction = Enum.KeyCode.ButtonX,
		-- Closes a page: NavigationHandler binds it, close buttons only show it.
		Close = Enum.KeyCode.ButtonB,
		-- The tutorial bubble's "Got it". Y, not X, so interacting is never swallowed by a hint.
		Acknowledge = Enum.KeyCode.ButtonY,
		-- Loads the next missing pantry ingredient shown on the mixer's floating card.
		MixerPantry = Enum.KeyCode.ButtonR1,
		-- Opens the recipe list from that card's dish name, to change the dish in work.
		MixerRecipes = Enum.KeyCode.ButtonL1,
		-- Opens the bakery from the HUD clock's Closed sign. Roblox gives R2 to tools; the game has none.
		OpenBakery = Enum.KeyCode.ButtonR2,
	},

	-- A cue on something that appears by itself (the evening's Next Day, a tutorial line) ignores
	-- presses for this long, so a press meant for what was there before cannot land on it.
	SettleSeconds = 1,
	-- The mixer prompt's activation radius: RB loads the pantry only within it (the server allows 14).
	MixerReach = 12,

	Badge = {
		-- Diameter of the badge as a share of its button's shorter side, clamped in layout pixels and
		-- drawn at its screen's scale. Sized for a TV across the room: the D-pad glyph's direction
		-- notch vanishes below about 24.
		Share = 0.34,
		MinSize = 24,
		MaxSize = 40,
		Stroke = 2,
		GlyphShare = 0.86,
		-- Above the button's artwork and its alert marks.
		ZIndex = 30,
		-- Gap to the button when the badge sits beside it.
		SideGap = 6,
		-- How far a corner or edge badge pulls back inside its button, as a share of its size.
		Inset = 0.3,
	},

	-- Gamepad focus ring drawn around the selected object (PlayerGui.SelectionImageObject). It takes the
	-- object's own rounding, or that of art covering at least Fill of it; Corner is for neither.
	Selection = {
		Color = Color3.fromRGB(255, 196, 0),
		Thickness = 3,
		Corner = UDim.new(0, 12),
		Fill = 0.9,
	},

	-- The HUD's glyph row on gamepad: the badge in each authored entry of HUD.Controls.GamepadHint,
	-- by entry name. NavigationHandler binds Menu and sinks Interact. Players always run, so RunHandler
	-- hides the authored Run entry instead of binding a key.
	Hints = {
		BadgeSize = 28,
		Keys = {
			Menu = Enum.KeyCode.ButtonY,
			Interact = Enum.KeyCode.ButtonX,
		},
	},
}
