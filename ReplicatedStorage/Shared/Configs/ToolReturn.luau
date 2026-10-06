--!strict
-- Local guide back to a tool's rack while the tool is carried: the outline of the rack's own model
-- where it stood, and the hint arrow beam from the player to it.
return {
	-- The engine skips a Highlight on an ordinary transparent part, but still draws one on glass. A
	-- near-invisible glass copy leaves only the outline.
	GhostMaterial = Enum.Material.Glass,
	GhostTransparency = 0.99,
	FillColor = Color3.new(1, 1, 1),
	FillTransparency = 1,
	OutlineColor = Color3.new(1, 1, 1),
	OutlineTransparency = 0,
	-- Visible through the kitchen walls, so the spot can be found from anywhere in the bakery.
	DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
}
