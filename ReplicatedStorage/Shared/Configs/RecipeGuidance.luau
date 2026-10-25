--!strict
-- Labels augment the authored recipe cards and mixer rows without changing recipe eligibility.

return {
	MaxNames = 2,
	TextSize = 16,
	MinTextSize = 11,
	-- The menu card's caption ends where the dish name starts (0.78) and is bottom-aligned, so on a
	-- small card, where the text floor makes it taller than its box, it grows up over the lock art
	-- instead of down over the name.
	Card = {
		Position = UDim2.fromScale(0.5, 0.61),
		Size = UDim2.fromScale(0.94, 0.34),
		IconPosition = UDim2.fromScale(0.5, 0.34),
		IconSize = UDim2.fromScale(0.38, 0.38),
	},
	Row = {
		Position = UDim2.new(0.5, -20, 1, -10),
		Size = UDim2.new(1, -280, 0, 18),
		-- Compact rows stack the chips under the name: between the chips and the reward, left of Start.
		CompactPosition = UDim2.new(0.5, -72, 0, 161),
		CompactSize = UDim2.new(1, -168, 0, 18),
	},
}
