--!strict
-- Number and time formatting for labels. Lifted out of UIHandler so views and their stories can use
-- it without pulling a handler into Shared.

--[[ Constants ]]--
-- From a million up, amounts are abbreviated so a long-running balance keeps its plate width.
local ABBREVIATIONS = {
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
}

--[[ Tables ]]--
local Format = {}

--[[ Handling ]]--
--- 123456 -> "123,456", 1234567 -> "1.23M". Commas, because testers read space-grouped amounts as a
--- bug. Displayed amounts are whole numbers; abbreviations round down, so a balance never reads as
--- more than it is.
function Format.Number(value: number): string
	local whole = math.round(math.abs(value))
	local sign = if value < 0 and whole > 0 then "-" else ""

	for _, step in ABBREVIATIONS do
		if whole >= step.Value then
			local hundredths = whole * 100 // step.Value
			local short = string.format("%d.%02d", hundredths // 100, hundredths % 100):gsub("%.?0+$", "")
			return `{sign}{short}{step.Suffix}`
		end
	end

	local grouped = tostring(whole):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return sign .. (grouped:gsub("^,", ""))
end

--- Seconds -> "M:SS", or "H:MM:SS" from an hour up so "60:32" never reads as minutes.
function Format.Time(seconds: number): string
	local clamped = math.max(seconds, 0)

	if clamped >= 3600 then
		return string.format("%d:%02d:%02d", clamped // 3600, (clamped % 3600) // 60, clamped % 60)
	end

	return string.format("%d:%02d", clamped // 60, clamped % 60)
end

--- Minutes since midnight -> "08:00". The bakery clock is a time of day, not a duration.
function Format.Clock(minutes: number): string
	local clamped = math.max(math.floor(minutes), 0)

	return string.format("%02d:%02d", (clamped // 60) % 24, clamped % 60)
end

--- Seconds -> "3h 20m" / "12m". For waits measured in hours, where "200:14" reads as nothing.
function Format.LongTime(seconds: number): string
	local clamped = math.max(seconds, 0)
	local hours = clamped // 3600
	local minutes = (clamped % 3600) // 60

	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end

	return string.format("%dm", minutes)
end

return Format
