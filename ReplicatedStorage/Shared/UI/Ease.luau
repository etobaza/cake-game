--!strict
-- Easing curves for timeline-driven feedback (coins, popups, celebrations). Input and output are
-- normalized: 0 at the start, 1 at the end; "Back" curves overshoot past 1 before settling.

--[[ Constants ]]--
-- Robert Penner's back constant: about 10% overshoot.
local BACK = 1.70158

--[[ Tables ]]--
local Ease = {}

--[[ Handling ]]--
function Ease.Clamp(t: number): number
	return math.clamp(t, 0, 1)
end

function Ease.OutCubic(t: number): number
	local x = 1 - Ease.Clamp(t)
	return 1 - x * x * x
end

function Ease.InQuad(t: number): number
	local x = Ease.Clamp(t)
	return x * x
end

--- Rises past 1 and settles; `strength` scales the overshoot (1 is about 10%).
function Ease.OutBack(t: number, strength: number?): number
	local c1 = BACK * (strength or 1)
	local c3 = c1 + 1
	local x = Ease.Clamp(t) - 1
	return 1 + c3 * x * x * x + c1 * x * x
end

--- Pulls back below 0 before leaving: the mirror of `OutBack`, for exits.
function Ease.InBack(t: number, strength: number?): number
	local c1 = BACK * (strength or 1)
	local c3 = c1 + 1
	local x = Ease.Clamp(t)
	return c3 * x * x * x - c1 * x * x
end

return Ease
