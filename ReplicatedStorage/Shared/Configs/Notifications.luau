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
	-- An open page's panel is never covered: the toast moves above, below or beside it, keeping this gap.
	PanelGap = 16,
	-- Narrowest logical width worth drawing beside a page; a narrower gap leaves the toast in place.
	MinSideWidth = 150,
	-- A slim strip: noticeable under the clock without covering the bakery.
	Wide = {
		Width = 320,
		Height = 50,
		Top = 64,
		TextSize = 18,
		MinTextSize = 14,
		TextInset = Vector2.new(24, 10),
	},
	-- Phones seat the clock in the topbar row, so the strip rises to just under Roblox's buttons;
	-- a clock still centred above it pushes it down through ClockGap.
	Compact = {
		Width = 300,
		Height = 50,
		Top = 12,
		TextSize = 18,
		MinTextSize = 14,
		TextInset = Vector2.new(22, 10),
	},
}
