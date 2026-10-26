--!strict
-- Level progression: 25 levels, XP accumulates inside the current level.

--[[ Constants ]]--
-- The whole ladder to level 25 costs about 5 500 XP: with the small dish prices of the design-sheet
-- economy a Lemon Cake-paced shift earns 40-50 XP early (about 550 an hour), so the recipe ladder
-- tops out after several hours of shifts. The base was 10 until playtesters reported levels (new
-- recipes) arriving faster than the coins for the stations and tables to cook and serve them; at
-- 14, level 5 takes 155 XP instead of 110, about four early shifts instead of three.
local XP_BASE = 14
local XP_POWER = 1.1

--[[ Tables ]]--
local Progression = {
	MaxLevel = 25,

	-- Level reward — recipes and story progress. Levels missing here do not move the story.
	-- Chapter number = position in this list; the texts live in the UI, only unlock points are here.
	StoryBeats = { 3, 6, 9, 12, 15, 18, 21, 25 },
}

--[[ Handling ]]--
-- How much XP it takes to leave this level for the next one. nil at max level.
function Progression.GetXPToNext(level: number): number?
	if level >= Progression.MaxLevel then
		return nil
	end

	return math.round(XP_BASE * level ^ XP_POWER)
end

-- Chapter unlocked by this level; nil if the level does not move the story.
function Progression.GetStoryStage(level: number): number?
	local index = table.find(Progression.StoryBeats, level)
	return index
end

return Progression
