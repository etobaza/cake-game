--!strict

export type ProfilerStats = {
	total: number,
	count: number,
	average: number,
	last: number,
	max: number,
	min: number,
}

local Profiler = {}

local _profileStats = {}
local _threadStacks = {}

--[[
    Begin profiling a section of code
    
    @param name Unique name for the profile section
]]
function Profiler.Begin(name: string)
	local thread = coroutine.running()

	if not _threadStacks[thread] then
		_threadStacks[thread] = {}
	end

	table.insert(_threadStacks[thread], {
		name = name,
		start = os.clock(),
	})
end

--[[
    End profiling a section of code
    
    @param name Name matching the ProfileBegin call
]]
function Profiler.End(name: string)
	local thread = coroutine.running()
	local stack = _threadStacks[thread]

	if not stack or #stack == 0 then
		print(`Profiler.End("{name}") called without matching ProfileBegin`)
		return
	end

	local entry = stack[#stack]

	if entry.name ~= name then
		print(`Profiler.End("{name}") mismatch. Expected "{entry.name}"`)
		return
	end

	table.remove(stack)

	local duration = os.clock() - entry.start

	-- Update statistics
	if not _profileStats[name] then
		_profileStats[name] = {
			total = 0,
			count = 0,
			average = 0,
			last = 0,
			max = 0,
			min = math.huge,
		}
	end

	local stats = _profileStats[name]
	stats.last = duration
	stats.total += duration
	stats.count += 1
	stats.average = stats.total / stats.count
	stats.max = math.max(stats.max, duration)
	stats.min = math.min(stats.min, duration)
end

--[[
    Get all profiling statistics
]]
function Profiler.GetStats()
	return table.clone(_profileStats)
end

--[[
    Reset all profiling statistics
]]
function Profiler.Reset()
	table.clear(_profileStats)
	table.clear(_threadStacks)
end

return Profiler
