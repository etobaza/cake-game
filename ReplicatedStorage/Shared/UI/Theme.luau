--!strict
-- The HUD's design language, measured off the authored StarterGui screens before the UI moved into
-- code. Every screen reads its colours, type and stroke weights from here so a change lands once.

--[[ Constants ]]--
-- The game's one type family. Every label in the authored HUD used it; only a handful of stray
-- SourceSans labels did not, and those were unstyled leftovers.
local FAMILY = "rbxassetid://12187374954"

--[[ Tables ]]--
local Theme = {}

Theme.Fonts = {
	Medium = Font.new(FAMILY, Enum.FontWeight.Medium),
	SemiBold = Font.new(FAMILY, Enum.FontWeight.SemiBold),
	Bold = Font.new(FAMILY, Enum.FontWeight.Bold),
	ExtraBold = Font.new(FAMILY, Enum.FontWeight.ExtraBold),
	Title = Font.new(FAMILY, Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic),
}

Theme.Colors = {
	-- Every label is a dark plate with a lighter face lifted a few percent above it.
	TextFace = Color3.fromRGB(255, 255, 255),
	TextShadow = Color3.fromRGB(0, 0, 0),
	-- Gains and boosts.
	Positive = Color3.fromRGB(43, 255, 0),
	-- The XP/quest accent, and the stroke on the quest bar.
	Gold = Color3.fromRGB(191, 140, 0),
	Cocoa = Color3.fromRGB(95, 51, 51),
	-- Panel fill and its outline, shared by every pop-up in the game.
	PanelFill = Color3.fromRGB(253, 234, 195),
	PanelEdge = Color3.fromRGB(238, 165, 75),
}

-- Progress fills run this gradient bottom to top.
Theme.ProgressGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 234, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 106, 0)),
})

-- Stroke thickness is in PIXELS, and the authored screens used values well under one — the outlines
-- there are effectively invisible. Reproduced as measured; raise them here if they were meant to show.
Theme.Stroke = {
	Hairline = 0.02,
	Thin = 0.04,
	Medium = 0.05,
	Thick = 0.06,
}

-- How far the light face sits above its shadow plate, in scale.
Theme.ShadowLift = 0.47

Theme.Corners = {
	Pill = UDim.new(1, 0),
	Bar = UDim.new(0.2678, 0),
	Button = UDim.new(0.1951, 0),
}

-- Logical UI pixels grow on desktop; each surface still fits its own safe rectangle.
Theme.TextScale = {
	ReferenceSize = Vector2.new(1280, 720),
	Minimum = 1,
	Maximum = 1.4,
}

-- Always-visible screen UI (HUD, overlays, pixel-sized billboards) keeps roughly the same share of
-- the screen on every device: it follows the reference canvas down to phones, floored for legibility.
Theme.ScreenScale = {
	ReferenceSize = Vector2.new(1280, 720),
	Minimum = 0.6,
	Maximum = 1,
	-- Legibility floors on small screens, in rendered pixels: text, and a side of a touch target.
	MinTextPixels = 10,
	MinTouchPixels = 44,
}

-- Billboards labelling a model (guest bubbles, meal progress) keep a constant world size: one layout
-- pixel spans StudsPerPixel, so they shrink with distance like the guest. Maximum stops a billboard
-- beside the camera from filling the screen.
Theme.WorldScale = {
	StudsPerPixel = 0.023,
	Maximum = 2,
}

return Theme
