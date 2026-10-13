--!strict
-- The small build label in the bottom-left corner (BuildLabelHandler), so testers can quote the
-- exact published version and server in their reports.

return {
	-- Shown instead of a version number in Studio, where PlaceVersion is not a published build.
	StudioText = "Studio",
	-- Characters of the server JobId appended after the version; 0 hides the server part.
	JobIdLength = 8,

	-- Pixels from the bottom-left corner of the device safe area.
	Offset = Vector2.new(6, 4),
	Size = Vector2.new(160, 14),
	TextSize = 12,
	TextColor = Color3.fromRGB(255, 255, 255),
	TextTransparency = 0.45,
	StrokeColor = Color3.fromRGB(0, 0, 0),
	StrokeTransparency = 0.6,
	-- Above the HUD and pages; the label never takes input, so it cannot block what lies beneath.
	DisplayOrder = 90,
}
