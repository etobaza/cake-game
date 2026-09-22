--!strict
-- Day cycle: prep with no timer, an 8 minute shift, manual summary. Plus customer flow and spills.

--[[ Modules ]]--
local TableConfig = require(script.Parent.TableMenus)

--[[ Tables ]]--
local DayCycle = {
	ShiftSeconds = 480,
	-- BP_DailyCycle checks for the last departing guest every three seconds.
	ClosingCheckSeconds = 3,
	-- One eight-minute shift represents the bakery's working day. Prep stays at opening time,
	-- Summary stays at closing time, while the lighting moves farther into the evening.
	OpenHour = 8,
	CloseHour = 16,
	-- Stop admitting guests five shop-clock minutes before closing (15:55).
	LastAdmissionMinutesBeforeClose = 5,
	EveningLightingHour = 18.25,

	MenuMin = 3,
	MenuMax = 5,

	-- Lemon Cake build 6596857: BP_ClientSpawner.ClientDelayTimer = 10 seconds.
	-- CustomerHandler applies the display-flow multiplier (0.5-2), independent of seat count.
	SpawnInterval = 10,
	-- Keep the opening responsive; subsequent arrivals use the reference game's interval.
	FirstSpawnDelay = 4,

	-- Guests allowed on top of the capacity: a short queue is pressure, a long one is only lost patience.
	QueueSlack = 2,

	-- How long a guest stays at the table with the dish before leaving. The seat stays taken for it,
	-- so this is the real cost of the last table being busy.
	EatSeconds = 6,

	-- Each new mixing/baking action rolls once. The first batch is guaranteed to make the tutorial
	-- spill; later batches use this chance until the authored pool is full.
	SpillChance = 0.34,
	SpillPlacementAttempts = 24,
	SpillSeparation = 5,
	-- The reference kitchen contains three reusable artist spill models.
	MaxSpills = 3,
	-- How much slower the player moves while standing in a spill.
	SpillSlowFactor = 0.55,
}

--[[ Handling ]]--
-- What the bakery can physically hold at once: a seat or a display slot each serve one guest.
function DayCycle.GetCapacity(tableCount: number, displaySlots: number): number
	return math.max(tableCount * TableConfig.SeatCount + displaySlots, 1)
end

function DayCycle.GetMaxActive(capacity: number): number
	return capacity + DayCycle.QueueSlack
end

-- Fraction of the real shift that has elapsed. Outside Shift, callers choose the frozen endpoint.
function DayCycle.GetShiftProgress(endsAt: number, now: number): number
	if endsAt <= 0 then
		return 0
	end

	local left = endsAt - now
	return math.clamp(1 - left / DayCycle.ShiftSeconds, 0, 1)
end

-- Minutes on the shop clock: Prep is frozen at 08:00, Shift advances to 16:00, Summary stays there.
function DayCycle.GetClockMinutes(phase: string, endsAt: number, now: number): number
	local openMinutes = DayCycle.OpenHour * 60
	local closeMinutes = DayCycle.CloseHour * 60
	if phase == "Summary" or phase == "Closing" then
		return closeMinutes
	end
	if phase ~= "Shift" then
		return openMinutes
	end

	local progress = DayCycle.GetShiftProgress(endsAt, now)
	return math.floor(openMinutes + (closeMinutes - openMinutes) * progress)
end

function DayCycle.CanAcceptCustomers(phase: string, endsAt: number, now: number): boolean
	if phase ~= "Shift" then
		return false
	end
	return DayCycle.GetClockMinutes(phase, endsAt, now)
		< DayCycle.CloseHour * 60 - DayCycle.LastAdmissionMinutesBeforeClose
end

-- Seating limits admission, but does not slow the arrival timer in a small bakery.
function DayCycle.GetSpawnInterval(): number
	return DayCycle.SpawnInterval
end

return DayCycle
