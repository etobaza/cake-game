--!strict
-- Day cycle: prep with no timer, a level-scaled shift, manual summary. Plus customer flow and spills.
-- Shift length and arrival gaps follow Lemon Cake build 6596857, BP_DailyCycle.

--[[ Modules ]]--
local TableConfig = require(script.Parent.TableMenus)

--[[ Tables ]]--
local DayCycle = {
	-- The open bakery runs a morning stage (08:00-12:00) and a lunch stage (12:00-16:00), each
	-- StageBaseSeconds + StageSecondsPerLevel * level long, so a shift lasts 3:25 at level 1 and
	-- 5:25 at level 25.
	StageBaseSeconds = 100,
	StageSecondsPerLevel = 2.5,
	-- Seconds between arrivals: SpawnBaseSeconds * (SpawnLevelBase - SpawnLevelStep * level), scaled
	-- by the display-flow multiplier (0.5-2). The quiet morning waits MorningSpawnMultiplier times longer.
	SpawnBaseSeconds = 15,
	SpawnLevelBase = 0.95,
	SpawnLevelStep = 0.01,
	MorningSpawnMultiplier = 2.5,
	-- Lunch starts at this share of the shift.
	LunchProgress = 0.5,
	-- Lunch brings the pending arrival forward to this share of the shorter lunch gap, as the
	-- original restarts its spawn timer on a new stage.
	StageFirstSpawnShare = 0.2,
	-- BP_DailyCycle checks for the last departing guest every three seconds.
	ClosingCheckSeconds = 3,
	-- After closing time the bakery waits for the guests still inside, as BP_DailyCycle does: each of
	-- them leaves on their own once served or out of patience, so the player can finish serving them.
	-- Only what cannot end by itself is cut off after ClosingMaxSeconds: a protected introduction
	-- guest, whose patience never runs out, and a body stuck on its way out.
	ClosingMaxSeconds = 30,
	-- Nothing keeps the day open longer: the longest patience (190) plus a meal and the walk out.
	ClosingHardMaxSeconds = 240,
	-- One shift represents the bakery's working day. Prep stays at opening time, Summary stays at
	-- closing time, while the lighting moves farther into the evening.
	OpenHour = 8,
	CloseHour = 16,
	-- Stop admitting guests five shop-clock minutes before closing (15:55).
	LastAdmissionMinutesBeforeClose = 5,
	EveningLightingHour = 18.25,
	-- Authored Fx parts whose unlit Beams fake sunlight through the bakery windows; the evening
	-- lighting switches them off (Shared/Sunbeams).
	SunbeamPartName = "RayPart",

	MenuMin = 3,
	MenuMax = 5,

	-- Keep the opening responsive; subsequent arrivals use the stage gap.
	FirstSpawnDelay = 0.5,
	-- An empty bakery calls its next guest in within this many seconds, whatever the timer says.
	EmptySpawnDelay = 1.5,
	-- A seated guest who finds only used places says so at most this often (CustomerHandler).
	DirtyTableNoticeSeconds = 20,
	-- Finishing the introduction sends this many guests in a row, RushSpawnInterval apart, so the
	-- player has work at once; the quiet morning then eases them in. Rush guests (and the first guest
	-- of a shift, and any guest arriving to an empty bakery) step in from the porch and choose in
	-- Orders.FirstGuestChooseSeconds.
	TutorialRushGuests = 1,
	RushSpawnInterval = 2,

	-- Guests allowed on top of the capacity: room for visitors roaming while every place is taken.
	QueueSlack = 2,

	-- How long a guest stays at the table with the dish before leaving. The seat stays taken for it,
	-- so this is the real cost of the last table being busy.
	EatSeconds = 6,

	-- After the introduction, each mixing/baking action rolls once until the authored pool is full.
	-- Players who have never mopped still receive one guaranteed spill on their first kitchen action.
	SpillChance = 0.34,
	SpillPlacementAttempts = 24,
	SpillSeparation = 8,
	-- The reference kitchen contains three reusable artist spill models.
	MaxSpills = 3,
	-- The artist puddles are drawn this much wider; the slowing area grows with them.
	SpillScale = 1.5,
	-- How much slower the player moves while standing in a spill.
	SpillSlowFactor = 0.4,
	Sweep = {
		PromptDistance = 6,
		-- Move only a nearby character to the player-facing edge of the authored puddle; enough to
		-- reach the edge from the middle of the widest scaled puddle.
		MaxAdjustment = 5,
		EdgeClearance = 0.65,
		FloorTolerance = 0.75,
		FloorProbeExtra = 1.5,
	},
}

--[[ Handling ]]--
-- What the bakery can physically hold at once: a seat or a display slot each serve one guest.
function DayCycle.GetCapacity(tableCount: number, displaySlots: number): number
	return math.max(tableCount * TableConfig.SeatCount + displaySlots, 1)
end

function DayCycle.GetMaxActive(capacity: number): number
	return capacity + DayCycle.QueueSlack
end

-- Length of a shift opened at this level; DayCycleHandler stores it on the day when the clock starts.
function DayCycle.GetShiftSeconds(level: number): number
	return 2 * (DayCycle.StageBaseSeconds + DayCycle.StageSecondsPerLevel * level)
end

-- Fraction of the real shift that has elapsed. Outside Shift, callers choose the frozen endpoint.
function DayCycle.GetShiftProgress(endsAt: number, shiftSeconds: number, now: number): number
	if endsAt <= 0 or shiftSeconds <= 0 then
		return 0
	end

	local left = endsAt - now
	return math.clamp(1 - left / shiftSeconds, 0, 1)
end

function DayCycle.IsLunch(progress: number): boolean
	return progress >= DayCycle.LunchProgress
end

-- Minutes on the shop clock: Prep is frozen at 08:00, Shift advances to 16:00, Summary stays there.
function DayCycle.GetClockMinutes(phase: string, endsAt: number, shiftSeconds: number, now: number): number
	local openMinutes = DayCycle.OpenHour * 60
	local closeMinutes = DayCycle.CloseHour * 60
	if phase == "Summary" or phase == "Closing" then
		return closeMinutes
	end
	if phase ~= "Shift" then
		return openMinutes
	end

	local progress = DayCycle.GetShiftProgress(endsAt, shiftSeconds, now)
	return math.floor(openMinutes + (closeMinutes - openMinutes) * progress)
end

function DayCycle.CanAcceptCustomers(phase: string, endsAt: number, shiftSeconds: number, now: number): boolean
	if phase ~= "Shift" then
		return false
	end
	return DayCycle.GetClockMinutes(phase, endsAt, shiftSeconds, now)
		< DayCycle.CloseHour * 60 - DayCycle.LastAdmissionMinutesBeforeClose
end

-- Seconds between arrivals before the display-flow multiplier. Seating limits admission, but does
-- not slow the arrival timer in a small bakery.
function DayCycle.GetSpawnInterval(level: number, progress: number): number
	local interval = DayCycle.SpawnBaseSeconds * (DayCycle.SpawnLevelBase - DayCycle.SpawnLevelStep * level)
	return if DayCycle.IsLunch(progress) then interval else interval * DayCycle.MorningSpawnMultiplier
end

return DayCycle
