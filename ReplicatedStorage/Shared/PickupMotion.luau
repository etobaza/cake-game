--!strict
-- Samples pickup arcs inside the existing prop renderers; owns no models or frame connections.

--[[ Modules ]]--
local Appearance = require(script.Parent.CarriedAppearance)
local Config = require(script.Parent.Configs.CarryPresentation)

--[[ Types ]]--
export type Flight = { Origin: Vector3, StartedAt: number }

--[[ Tables ]]--
local PickupMotion = {}

--[[ Handling ]]--
function PickupMotion.Begin(item: Appearance.Item?, now: number): Flight?
	local origin = item and item.PickupOrigin
	local pickedAt = item and item.PickupAt
	if not origin or not pickedAt or now < pickedAt or now - pickedAt > Config.PickupMaxAge then
		return nil
	end
	return { Origin = Vector3.new(origin[1], origin[2], origin[3]), StartedAt = now }
end

-- Origins are mesh centres. FoodModel targets are bottoms; tools use their part centres.
function PickupMotion.Sample(flight: Flight?, target: CFrame, centreOffset: Vector3, now: number): CFrame
	if not flight then
		return target
	end
	local alpha = math.clamp((now - flight.StartedAt) / Config.PickupSeconds, 0, 1)
	local centre = target:PointToWorldSpace(centreOffset)
	if alpha >= 1 or (centre - flight.Origin).Magnitude > Config.PickupMaxDistance then
		return target
	end
	local eased = 1 - (1 - alpha) ^ 3
	local position = flight.Origin:Lerp(centre, eased)
		+ Vector3.yAxis * (4 * Config.PickupArcHeight * eased * (1 - eased))
	return target + (position - centre)
end

return PickupMotion
