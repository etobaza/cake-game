--!strict

return {
	-- The most a hovered or selected control grows; ButtonRow lowers it where the row has less room.
	HoverScale = 1.08,
	PressScale = 0.94,
	Spring = { frequency = 6, dampingRatio = 1 },
	-- A white wash over the hovered control's background, below its caption.
	Highlight = {
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.8,
		-- Image backgrounds draw their own rounded outline; the wash stays inside it.
		ImageInset = 1,
		ImageCorner = UDim.new(0, 7),
	},
}
