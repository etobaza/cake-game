--!strict
-- Number and time formatting for labels. Lifted out of UIHandler so views and their stories can use
-- it without pulling a handler into Shared.

--[[ Tables ]]--
local Format = {}

--[[ Handling ]]--
--- 1234567 -> "1 234 567". Thin spaces, not commas -- that is how the HUD was authored.
--- Design-sheet prices carry cents (5.25), so a fractional value keeps two decimals.
function Format.Number(value: number): string
	local totalCents = math.round(math.abs(value) * 100)
	local whole = math.floor(totalCents / 100)
	local text = tostring(whole)
	local grouped = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	local formatted = (grouped:gsub("^%s+", ""))

	local cents = totalCents - whole * 100
	if cents > 0 then
		formatted ..= string.format(".%02d", cents)
	end

	return if value < 0 and totalCents > 0 then `-{formatted}` else formatted
end

--- Seconds -> "M:SS".
function Format.Time(seconds: number): string
	local clamped = math.max(seconds, 0)

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
