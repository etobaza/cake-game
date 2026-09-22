--!strict
-- Argument checks for network packets. Packet has no sanitizing, so we check by hand.

--[[ Constants ]]--
local MAX_ID_LENGTH = 48

--[[ Tables ]]--
local Sanitize = {}

--[[ Handling ]]--
-- String identifier of a registry/state. Returns nil when it cannot be trusted.
function Sanitize.Id(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	if #value == 0 or #value > MAX_ID_LENGTH then
		return nil
	end

	return value
end

-- Integer index within [1, max].
function Sanitize.Index(value: any, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end

	if value ~= math.floor(value) or value < 1 or value > max then
		return nil
	end

	return value
end

-- Array of identifiers without duplicates, no longer than maxCount.
-- An empty array is a valid draft: the evening planner may clear tomorrow's menu before refilling it.
function Sanitize.IdList(value: any, maxCount: number): { string }?
	if typeof(value) ~= "table" then
		return nil
	end

	local list = value :: { any }
	if #list > maxCount then
		return nil
	end

	local seen: { [string]: boolean } = {}
	local result: { string } = {}

	for _, raw in list do
		local id = Sanitize.Id(raw)
		if not id or seen[id] then
			return nil
		end

		seen[id] = true
		result[#result + 1] = id
	end

	return result
end

return Sanitize
