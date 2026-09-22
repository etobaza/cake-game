--!strict
-- Pre-built bakeries: one per player, claimed on join, released on leave.
-- Anchors (building/entrance/spawn/spill points) are authored ONCE, in the reference bakery's
-- Anchors folder: drag parts in Studio, every bakery follows. The other bakeries are rigid copies;
-- BaseHandler maps anchors onto them through the origin part transform.

--[[ Tables ]]--
local Base = {
	-- The authored world is one Roblox package mounted in Workspace; the folders below sit inside it.
	WorldFolderName = "World",
	-- Pre-built bakeries.
	BakeriesFolderName = "Bakeries",

	-- The bakery that carries the Anchors folder; the rest map onto it by origin.
	TemplateName = "BakeryOrange",

	-- Part every bakery has at the same authored spot. A bakery's transform is
	-- origin.CFrame * templateOrigin.CFrame:Inverse().
	OriginPath = { "1ndFloor", "Fx", "effect" },

	-- Owner attribute on the claimed bakery; systems find the owner of an object through it.
	OwnerAttribute = "OwnerUserId",

	-- Parts named after a building (or Entrance / Spawn) live here. CFrame is the floor point.
	AnchorsFolderName = "Anchors",
	EntranceAnchorName = "Entrance",
	SpawnAnchorName = "Spawn",
	-- Spill spots: spill_1, spill_2, ...
	SpillAnchorPrefix = "spill",

	-- Folders inside a bakery hidden while it is owned: artist previews of upgrades that
	-- BuildingHandler spawns for real from the player's stats.
	PreviewFolders = {
		{ "1ndFloor", "Cafe", "Upgrades" },
		{ "1ndFloor", "Kitchen", "Upgrades" },
		{ "1ndFloor", "Garden", "Upgrades" },
	},

	-- The board above the entrance. Note the authored leading space in " exterior".
	-- Its label reads "Player's Bakery" while the place is free; a claimed one takes the owner's name.
	-- The vacant text is read off the instance rather than kept here, so re-wording the sign in Studio
	-- needs no code change.
	SignPath = { "1ndFloor", " exterior", "Sign" },
	SignOwnedFormat = "%s's Bakery",

	-- PivotTo on a character places the rig centre, not the feet.
	CharacterLift = 3,

	DataTimeout = 10,
	CharacterTimeout = 5,
}

return Base
