--!strict
-- Read the authored sidewalk nearest the entrance; keep street legs on that same side.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Guests).Street

local StreetRoute = {}
export type Route = {
	Center: Vector3,
	First: Vector3,
	Last: Vector3,
	Porch: Vector3,
	ExitFirst: Vector3,
	ExitLast: Vector3,
}

function StreetRoute.Build(door: BasePart, porch: Vector3): Route?
	local folder: Instance? = workspace
	for _, name in Config.SidewalkPath do
		folder = folder and folder:FindFirstChild(name)
	end
	if not folder then
		return nil
	end
	local nearest: BasePart? = nil
	local distance = math.huge
	for _, part in folder:GetDescendants() do
		if not part:IsA("BasePart") or part.Name ~= Config.SidewalkName then
			continue
		end
		local offset = part.CFrame:PointToObjectSpace(door.Position)
		local along = math.clamp(offset.Z, -part.Size.Z / 2, part.Size.Z / 2)
		local candidate = part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y / 2, along))
		local gap = (candidate - door.Position).Magnitude
		if gap < distance then
			nearest = part
			distance = gap
		end
	end
	if not nearest then
		return nil
	end
	local offset = nearest.CFrame:PointToObjectSpace(door.Position)
	local side = if offset.X >= 0 then 1 else -1
	local lane = side * math.max(0, nearest.Size.X / 2 - Config.LaneOffset)
	local limit = math.max(0, nearest.Size.Z / 2 - Config.EndInset)
	local along = math.clamp(offset.Z, -limit, limit)
	local function point(z: number): Vector3
		local world = nearest.CFrame:PointToWorldSpace(Vector3.new(lane, 0, z))
		-- One authored sidewalk is flipped upside down; local +Y is not its walking surface.
		return Vector3.new(world.X, nearest.Position.Y + nearest.Size.Y / 2, world.Z)
	end
	return {
		Center = point(along),
		First = point(math.max(-limit, along - Config.HalfLength)),
		Last = point(math.min(limit, along + Config.HalfLength)),
		Porch = porch,
		ExitFirst = point(-limit),
		ExitLast = point(limit),
	}
end

function StreetRoute.Append(points: { Vector3 }, from: Vector3, destination: Vector3): ()
	local steps = math.max(1, math.ceil((destination - from).Magnitude / Config.PointSpacing))
	for step = 1, steps do
		points[#points + 1] = from:Lerp(destination, step / steps)
	end
end

function StreetRoute.Enter(route: Route, position: Vector3): { Vector3 }
	local points: { Vector3 } = {}
	StreetRoute.Append(points, position, route.Center)
	StreetRoute.Append(points, route.Center, route.Porch)
	return points
end

function StreetRoute.Circuit(): { Vector3 }
	local folder: Instance? = workspace
	for _, name in Config.SidewalkPath do
		folder = folder and folder:FindFirstChild(name)
	end
	if not folder then
		return {}
	end
	local parts: { BasePart } = {}
	for _, part in folder:GetDescendants() do
		if part:IsA("BasePart") and part.Name == Config.SidewalkName then
			parts[#parts + 1] = part
		end
	end
	if #parts ~= 2 then
		return {}
	end
	table.sort(parts, function(a, b)
		return a.Position.X < b.Position.X
	end)
	local points: { Vector3 } = {}
	for index, part in parts do
		local outward = Vector3.new(if index == 1 then -1 else 1, 0, 0)
		local side = if part.CFrame.RightVector:Dot(outward) >= 0 then 1 else -1
		local lane = side * math.max(0, part.Size.X / 2 - Config.LaneOffset)
		local limit = math.max(0, part.Size.Z / 2 - Config.EndInset)
		local ends: { Vector3 } = {}
		for _, z in { -limit, limit } do
			local point = part.CFrame:PointToWorldSpace(Vector3.new(lane, 0, z))
			ends[#ends + 1] = Vector3.new(point.X, part.Position.Y + part.Size.Y / 2, point.Z)
		end
		table.sort(ends, function(a, b)
			return a.Z < b.Z
		end)
		points[#points + 1] = ends[if index == 1 then 1 else 2]
		points[#points + 1] = ends[if index == 1 then 2 else 1]
	end
	return points
end

function StreetRoute.NextNode(circuit: { Vector3 }, position: Vector3, direction: number): number
	local best, distance = 1, math.huge
	for index, first in circuit do
		local nextIndex = index % #circuit + 1
		local delta = circuit[nextIndex] - first
		local along = math.clamp((position - first):Dot(delta) / delta:Dot(delta), 0, 1)
		local gap = (position - (first + delta * along)).Magnitude
		if gap < distance then
			distance = gap
			best = if direction == 1 then nextIndex else index
		end
	end
	return best
end

function StreetRoute.IsNearby(route: Route, position: Vector3): boolean
	local flat = Vector3.new(position.X, route.Center.Y, position.Z)
	local lane = (route.ExitLast - route.ExitFirst).Unit
	local offset = flat - route.Center
	return offset.Magnitude <= Config.AdmissionDistance
		and (offset - lane * offset:Dot(lane)).Magnitude <= Config.LaneOffset
end

return StreetRoute
