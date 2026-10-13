--!strict
-- Scheduled live events. Every server computes the same UTC slots, so the event id is derived from
-- the slot itself and all servers agree on it without any messaging.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local Timeline = require(ReplicatedStorage.Shared.LiveEventTimeline)

--[[ Constants ]]--
local DAY = 86400

--[[ Tables ]]--
local Schedule = {}

--[[ Private Functions ]]--
local function runsOn(entry: Config.ScheduleEntry, slot: number): boolean
	local weekdays = entry.Weekdays
	if not weekdays then
		return true
	end
	local weekday = (os.date("!*t", slot) :: any).wday
	return table.find(weekdays, weekday) ~= nil
end

--[[ Handling ]]--
--- The scheduled event that should be running at `now` (unix seconds), if any. Yesterday's slot
--- is checked too, for an event that runs past midnight UTC.
function Schedule.Due(now: number): Timeline.State?
	local today = now - now % DAY
	for _, entry in Config.Schedule.Entries do
		if not Timeline.GetScript(entry.Script) then
			continue
		end
		for _, day in { today, today - DAY } do
			local slot = day + entry.Hour * 3600 + entry.Minute * 60
			local state: Timeline.State = { Id = `schedule:{entry.Script}:{slot}`, ScriptId = entry.Script, StartsAt = slot }
			if runsOn(entry, slot) and Timeline.IsLive(state, now) then
				return state
			end
		end
	end
	return nil
end

return Schedule
