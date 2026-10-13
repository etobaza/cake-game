--!strict
-- Pixel geometry for the existing Assets.Prompt artwork; world anchoring stays in PromptHandler.

return {
	CompactWidth = 700,
	CompactHeight = 500,
	EdgePadding = 16,
	-- Proximity plates remain compact even when pages use a larger desktop density.
	MaximumScale = 1,
	WideSize = Vector2.new(180, 64),
	CompactSize = Vector2.new(168, 60),
	StatusSize = Vector2.new(176, 44),
	IconSize = 32,
	IconPosition = UDim2.fromScale(0.16, 0.5),
	MinTextSize = 12,
	NameTextSize = 17,
	ActionTextSize = 15,
	StatusTextSize = 14,
	NamePosition = UDim2.fromScale(0.63, 0.3),
	NameSize = UDim2.fromScale(0.65, 0.44),
	ActionPosition = UDim2.fromScale(0.63, 0.75),
	ActionSize = UDim2.fromScale(0.65, 0.3),
	-- The status line's box decides its lettering: inside this billboard the scaled text fills the
	-- box and does not honour its UITextSizeConstraint, so the box is kept to about half the sign's
	-- height and inside its nailed ends. Longer lines still shrink to fit the width.
	StatusNameSize = UDim2.fromScale(0.8, 0.5),
	StatusPlateSize = UDim2.fromScale(0.98, 0.88),
}
