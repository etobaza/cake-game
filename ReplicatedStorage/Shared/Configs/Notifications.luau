--!strict
-- Logical pixel sizes and display layer for the existing authored status toast.

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
		Width = 320,
		Height = 72,
		Top = 44,
		TextSize = 18,
		MinTextSize = 16,
		TextInset = Vector2.new(24, 12),
	},
}
