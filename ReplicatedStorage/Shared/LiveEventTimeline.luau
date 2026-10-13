--!strict
-- Admin abuse timeline math shared by the server and every client. A live event is only an id, a
-- script id and an absolute start time (workspace:GetServerTimeNow()); everything else, from the
-- current line to the end of the event, is derived from the config so no line is ever networked.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)

--[[ Types ]]--
export type State = {
	-- Unique per event start; an empty id is "no event".
	Id: string,
	ScriptId: string,
	StartsAt: number,
}

--[[ Private Variables ]]--
-- Lines sorted by time, per script id, built on first use.
local sortedLines: { [string]: { Config.Line } } = {}

--[[ Tables ]]--
local LiveEventTimeline = {}

--[[ Handling ]]--
function LiveEventTimeline.GetScript(scriptId: string): Config.Script?
	return Config.Scripts[scriptId]
end

function LiveEventTimeline.GetLines(scriptId: string): { Config.Line }
	local cached = sortedLines[scriptId]
	if cached then
		return cached
	end

	local definition = Config.Scripts[scriptId]
	local lines: { Config.Line } = {}
	if definition then
		for _, line in definition.Lines do
			if Config.Cast[line.Speaker] then
				lines[#lines + 1] = line
			end
		end
		table.sort(lines, function(a: Config.Line, b: Config.Line): boolean
			return a.At < b.At
		end)
	end
	sortedLines[scriptId] = lines
	return lines
end

--- Cast ids on stage for a script: every speaker, in order of their first line.
function LiveEventTimeline.GetCast(scriptId: string): { string }
	local cast: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, line in LiveEventTimeline.GetLines(scriptId) do
		if not seen[line.Speaker] then
			seen[line.Speaker] = true
			cast[#cast + 1] = line.Speaker
		end
	end
	return cast
end

function LiveEventTimeline.EndsAt(state: State): number
	local definition = Config.Scripts[state.ScriptId]
	return state.StartsAt + (if definition then definition.Duration else 0)
end

--- Started and not finished yet.
function LiveEventTimeline.IsLive(state: State?, now: number): boolean
	return state ~= nil and now >= state.StartsAt and now < LiveEventTimeline.EndsAt(state)
end

function LiveEventTimeline.IsOver(state: State, now: number): boolean
	return now >= LiveEventTimeline.EndsAt(state)
end

--- The line on screen `elapsed` seconds into the script, with its index; nil between lines.
function LiveEventTimeline.LineAt(scriptId: string, elapsed: number): (number?, Config.Line?)
	local lines = LiveEventTimeline.GetLines(scriptId)
	for index = #lines, 1, -1 do
		local line = lines[index]
		if line.At > elapsed then
			continue
		end
		local nextLine = lines[index + 1]
		local hideAt = line.At + Config.Speech.LineSeconds
		if nextLine then
			hideAt = math.min(hideAt, nextLine.At)
		end
		if elapsed < hideAt then
			return index, line
		end
		return nil, nil
	end
	return nil, nil
end

return LiveEventTimeline
