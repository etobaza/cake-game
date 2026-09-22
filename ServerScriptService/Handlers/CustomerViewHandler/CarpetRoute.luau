--!strict
-- A small weighted graph over the authored blue runner's centre lines. Off-carpet edges remain
-- available, so guests can leave the runner for their reserved chair or display approach.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local CollisionConfig = require(ReplicatedStorage.Shared.Configs.Collision)
local GuestsConfig = require(ReplicatedStorage.Shared.Configs.Guests)

--[[ Constants ]]--
local CONFIG = GuestsConfig.CarpetRoute
local EPSILON = 0.05

--[[ Types ]]--
type Strip = { Start: Vector3, Finish: Vector3 }
type Node = { Position: Vector3, Strip: number? }

--[[ Tables ]]--
local CarpetRoute = {}

--[[ Private Functions ]]--
local function Project(strip: Strip, point: Vector3): Vector3
	local direction = strip.Finish - strip.Start
	local alpha = math.clamp((point - strip.Start):Dot(direction) / direction:Dot(direction), 0, 1)
	return strip.Start + direction * alpha
end

local function GetStrips(base: Instance, floorY: number): { Strip }
	local carpet: Instance? = base
	for _, name in CONFIG.Path do
		carpet = carpet and carpet:FindFirstChild(name)
	end
	local strips: { Strip } = {}
	if not carpet then
		return strips
	end

	for _, part in carpet:GetDescendants() do
		if not part:IsA("BasePart") or part.MaterialVariant ~= CONFIG.MaterialVariant then
			continue
		end
		local alongX = part.Size.X > part.Size.Z
		local offset = if alongX then Vector3.new(part.Size.X / 2, 0, 0) else Vector3.new(0, 0, part.Size.Z / 2)
		local first = part.CFrame:PointToWorldSpace(-offset)
		local last = part.CFrame:PointToWorldSpace(offset)
		first = Vector3.new(first.X, floorY, first.Z)
		last = Vector3.new(last.X, floorY, last.Z)
		if (last - first).Magnitude <= EPSILON then
			continue
		end
		table.insert(strips, { Start = first, Finish = last })
	end
	return strips
end

local function AddNode(nodes: { Node }, position: Vector3, strip: number): ()
	for _, node in nodes do
		if node.Strip == strip and (node.Position - position).Magnitude < EPSILON then
			return
		end
	end
	table.insert(nodes, { Position = position, Strip = strip })
end

local function ClosestNode(nodes: { Node }, point: Vector3, params: RaycastParams): number?
	local closest: number? = nil
	local best = math.huge
	local lift = Vector3.new(0, CONFIG.ObstacleHeight, 0)
	for index = 3, #nodes do
		local delta = nodes[index].Position - point
		if delta.Magnitude >= best then
			continue
		end
		if delta.Magnitude > EPSILON and workspace:Raycast(point + lift, delta, params) then
			continue
		end
		closest, best = index, delta.Magnitude
	end
	return closest
end

--[[ Handling ]]--
-- Includes the exact destination, excludes the starting point. Missing carpet preserves direct travel.
function CarpetRoute.Build(base: Instance?, from: Vector3, destination: Vector3): { Vector3 }
	if not base then
		return { destination }
	end
	local strips = GetStrips(base, destination.Y)
	if #strips == 0 then
		return { destination }
	end
	local start = Vector3.new(from.X, destination.Y, from.Z)
	local directDistance = (destination - start).Magnitude
	if directDistance <= CONFIG.DirectDistance then
		return { destination }
	end
	local nodes: { Node } = { { Position = start }, { Position = destination } }
	for index, strip in strips do
		AddNode(nodes, strip.Start, index)
		AddNode(nodes, strip.Finish, index)
		AddNode(nodes, Project(strip, start), index)
		AddNode(nodes, Project(strip, destination), index)
		-- Project both ends to connect perpendicular junctions and small authored gaps.
		for otherIndex, other in strips do
			if index == otherIndex then
				continue
			end
			AddNode(nodes, Project(strip, other.Start), index)
			AddNode(nodes, Project(strip, other.Finish), index)
		end
	end

	local params = RaycastParams.new()
	params.CollisionGroup = CollisionConfig.Groups.Guest
	params.RespectCanCollide = true
	-- Join and leave at the closest reachable points. A cost discount alone still lets display
	-- visitors cut across the room because their destination is on the entrance side of the runner.
	local entry = ClosestNode(nodes, start, params)
	local exit = ClosestNode(nodes, destination, params)
	if not entry or not exit then
		return { destination }
	end
	local lift = Vector3.new(0, CONFIG.ObstacleHeight, 0)
	local distances: { number } = table.create(#nodes, math.huge)
	local previous: { [number]: number } = {}
	local visited: { [number]: boolean } = {}
	distances[1] = 0
	for _ = 1, #nodes do
		local current: number? = nil
		local best = math.huge
		for index, distance in distances do
			if not visited[index] and distance < best then
				current, best = index, distance
			end
		end
		if not current or current == 2 then
			break
		end
		visited[current] = true
		local node = nodes[current]
		for index, neighbor in nodes do
			if visited[index] then
				continue
			end
			if current == 1 and index ~= entry then
				continue
			end
			if index == 2 and current ~= exit then
				continue
			end
			local delta = neighbor.Position - node.Position
			local cost = if node.Strip and node.Strip == neighbor.Strip then CONFIG.TravelCost else 1
			local distance = best + delta.Magnitude * cost
			if distance >= distances[index] then
				continue
			end
			if delta.Magnitude > EPSILON and workspace:Raycast(node.Position + lift, delta, params) then
				continue
			end
			distances[index] = distance
			previous[index] = current
		end
	end

	if not previous[2] then
		return { destination }
	end
	local reversed: { Vector3 } = {}
	local index = 2
	while index ~= 1 do
		table.insert(reversed, nodes[index].Position)
		index = previous[index]
	end
	local points: { Vector3 } = {}
	local last = start
	local distance = 0
	for pointIndex = #reversed, 1, -1 do
		local point = reversed[pointIndex]
		if (point - last).Magnitude < EPSILON and pointIndex ~= 1 then
			continue
		end
		table.insert(points, point)
		distance += (point - last).Magnitude
		last = point
	end
	-- Carpet is a preference: do not send two nearby guests on a disproportionate round trip.
	if distance > directDistance * CONFIG.MaxDetourRatio then
		return { destination }
	end
	return points
end

return CarpetRoute
