--!strict
-- Resolves the accepted pickup's world centre before its source is hidden or cleared.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)

--[[ Tables ]]--
local PickupOrigin = {}

--[[ Private Functions ]]--
local function centre(source: Instance): Vector3?
	if source:IsA("BasePart") then
		return source.Position
	end
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum
	local found = false
	for _, part in source:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 1 then
			continue
		end
		local frame, size = part.CFrame, part.Size
		local reach = (
			frame.RightVector:Abs() * size.X
			+ frame.UpVector:Abs() * size.Y
			+ frame.LookVector:Abs() * size.Z
		) / 2
		minimum = minimum:Min(part.Position - reach)
		maximum = maximum:Max(part.Position + reach)
		found = true
	end
	return if found then (minimum + maximum) / 2 else nil
end

--[[ Handling ]]--
function PickupOrigin.ForBuilding(building: any): Vector3
	local food = building.FoodVisual
	if food then
		return centre(food.Root) or food.Frame.Position
	end
	local source = Buildings.WorldModel(building.Part) or building.Part
	return centre(source) or building.Part.Position
end

function PickupOrigin.ForDelivery(building: any, index: number): Vector3?
	local visual = building.Visual
	local frame = visual and visual.Frames[index]
	return if visual then visual:GetPickupOrigin(index) or (frame and frame.Position) else nil
end

return PickupOrigin
