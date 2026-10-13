--!strict
-- HUD layout tuning read by Shared/UI/HudLayout, Shared/UI/HydrateHud and the HUD invite row.

return {
	-- Below either logical size the HUD switches to its compact (phone) arrangement.
	CompactWidth = 700,
	CompactHeight = 500,
	-- Adapts the authored Quests.Container.Quest.Main reward badge, which now shows the next goal's
	-- price. StarterGui is place-only, so these overrides restate the badge geometry at runtime until
	-- the artwork itself is redrawn; all values are scales of the authored parent.
	QuestPrice = {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.19),
		Size = UDim2.fromScale(0.39, 0.385),
		-- Gap between the coin icon and the price inside the badge's UIListLayout.
		Padding = UDim.new(0.04, 0),
		IconSize = UDim2.fromScale(0.25, 0.9),
		LabelSize = UDim2.fromScale(0.7, 0.9),
		-- Dark lettering and outline, so the price reads on the light badge.
		TextColor = Color3.new(0, 0, 0),
	},
}
