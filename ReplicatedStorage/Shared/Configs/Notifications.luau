--!strict
-- Logical pixel sizes and display layer for the existing authored status toast. StatusLayout
-- multiplies sizes by the desktop page density (at least 1) and the screen density (at most 1), so
-- compact (phone) screens draw them at about 0.6.

return {
	-- Toasts clear tutorial speech while staying below purchase receipts.
	DisplayOrder = 58,
	CompactWidth = 700,
	CompactHeight = 500,
	EdgePadding = 12,
	ClockGap = 16,
	Wide = {
		Width = 420,
		Height = 76,
		Top = 64,
		TextSize = 22,
		MinTextSize = 18,
		TextInset = Vector2.new(32, 16),
	},
	Compact = {
		Width = 400,
		Height = 76,
		Top = 44,
		TextSize = 22,
		MinTextSize = 18,
		TextInset = Vector2.new(28, 14),
	},
}
