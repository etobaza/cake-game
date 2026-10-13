--!strict
-- Labels augment the authored recipe cards and mixer rows without changing recipe eligibility.

return {
	MaxNames = 2,
	TextSize = 16,
	MinTextSize = 11,
	Card = {
		Position = UDim2.fromScale(0.5, 0.67),
		Size = UDim2.fromScale(0.94, 0.23),
		IconPosition = UDim2.fromScale(0.5, 0.34),
		IconSize = UDim2.fromScale(0.38, 0.38),
	},
	Row = {
		Position = UDim2.new(0.5, -20, 1, -10),
		Size = UDim2.new(1, -280, 0, 18),
	},
}
