--!strict
return {
	Tag = "FoodBurnMaterial",
	FadeAttribute = "FoodBurnFade",
	-- BP_Item.MaterialBurn: cubic zero-tangent keys (15, 0), (28, 1), (30, 1).
	StartFraction = 15 / 30,
	EndFraction = 28 / 30,
	FadeSteps = 128,
	-- MASTER_FoodFade's cooked pixel shader, before scene exposure and selection highlighting.
	OverlayDouble = Vector3.new(0.427084, 0.176358, 0.129414),
	GrayWeights = Vector3.new(0.141452, 0.145833, 0.046637),
	Desaturation = 0.1,
	-- cake-game: the fully burnt end of the fade (the dial's red burn mark) reads as charcoal, not
	-- the original's browned crust. Linear RGB, mixed over the tinted colour.
	Charcoal = Vector3.new(0.012, 0.009, 0.008),
	CharcoalBlend = 0.95,
	-- Bound client texture memory while preserving the source UVs and painted pattern.
	TextureSize = 512,
	RefreshSeconds = 0.15,
	WorkBudgetSeconds = 0.003,
	RenderDistance = 96,
}
