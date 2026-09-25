--!strict
-- Head-local bounds keep food outside protruding avatar faces, including head accessories.
local Clearance = {}

local function headAccessory(accessory: Accessory, head: BasePart): boolean
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	for _, child in handle:GetChildren() do
		if child:IsA("Weld") and (child.Part0 == head or child.Part1 == head) then
			return true
		end

		if child:IsA("Attachment") and head:FindFirstChild(child.Name) then
			return true
		end
	end

	return false
end

function Clearance.Collect(model: Model, head: BasePart): { BasePart }
	local parts = { head }

	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part == head or part.Transparency >= 1 then
			continue
		end

		local accessory = part:FindFirstAncestorWhichIsA("Accessory")
		local attachedToHead = part:IsDescendantOf(head) or (accessory and headAccessory(accessory, head))
		if attachedToHead then
			parts[#parts + 1] = part
		end
	end

	return parts
end

local function boundsInHead(head: BasePart, part: BasePart): (Vector3, Vector3)
	local frame = head.CFrame:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local reach = frame.RightVector:Abs() * half.X + frame.UpVector:Abs() * half.Y + frame.LookVector:Abs() * half.Z

	return frame.Position, reach
end

function Clearance.Front(head: BasePart, parts: { BasePart }, center: Vector3, radius: number): number?
	local front: number? = nil

	for _, part in parts do
		if not part.Parent then
			continue
		end

		local position, reach = boundsInHead(head, part)
		local overlapsX = math.abs(position.X - center.X) <= reach.X + radius
		local overlapsY = math.abs(position.Y - center.Y) <= reach.Y + radius
		if not overlapsX or not overlapsY then
			continue
		end

		front = math.min(front or math.huge, position.Z - reach.Z)
	end

	return front
end

function Clearance.Target(
	head: BasePart,
	parts: { BasePart },
	foodSize: Vector3,
	mouthOffset: Vector2,
	gap: number
): Vector3
	local center = Vector3.new(mouthOffset.X, mouthOffset.Y, 0)
	local radius = foodSize.Magnitude / 2
	local front = Clearance.Front(head, parts, center, radius) or -head.Size.Z / 2

	return head.CFrame:PointToWorldSpace(Vector3.new(center.X, center.Y, front - radius - gap))
end

function Clearance.KeepOutside(
	head: BasePart,
	parts: { BasePart },
	foodFrame: CFrame,
	foodSize: Vector3,
	gap: number
): CFrame
	local center = (foodFrame * CFrame.new(0, foodSize.Y / 2, 0)).Position
	local localCenter = head.CFrame:PointToObjectSpace(center)
	local radius = foodSize.Magnitude / 2
	local front = Clearance.Front(head, parts, localCenter, radius)
	if not front then
		return foodFrame
	end

	local correction = math.max(0, localCenter.Z + radius + gap - front)

	return foodFrame + head.CFrame.LookVector * correction
end

return Clearance
