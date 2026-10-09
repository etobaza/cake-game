--!strict
-- Leads world guidance through doorways. When a target lies in another room of a bakery than the
-- local player, the waypoint is the first doorway on the shortest room-to-room path instead of the
-- target itself, so the hand and beam never point through a wall. Once the player walks through,
-- the next doorway or the target takes over.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Config = require(ReplicatedStorage.Shared.Configs.Hint).Route
local World = require(ReplicatedStorage.Shared.World)

--[[ Types ]]--
type Edge = { a: string, b: string, point: Vector3, door: Instance, count: number }
type Graph = { edges: { Edge }, built: number }

--[[ Tables ]]--
local HintRoute = {}

--[[ Private Variables ]]--
local Graphs: { [Instance]: Graph } = {}
local Params = RaycastParams.new()
Params.FilterType = Enum.RaycastFilterType.Include
Params.IgnoreWater = true
local FloorsBuilt = -math.huge

--[[ Private Functions ]]--
-- Floor folders of every bakery go into one include list; a hit names both bakery and room.
local function refreshFloors(): ()
	local now = os.clock()
	if now - FloorsBuilt < Config.RefreshSeconds then
		return
	end
	FloorsBuilt = now

	local floors: { Instance } = {}
	local bakeries = World.Bakeries()
	local list: { Instance } = if bakeries then bakeries:GetChildren() else {}
	for _, bakery in list do
		for _, path in Config.Floors do
			local folder = Buildings.ResolvePath(bakery, path)
			if folder then
				table.insert(floors, folder)
			end
		end
	end
	Params.FilterDescendantsInstances = floors
end

-- Bakery and floor folder above which a point stands, or nil when it is above none.
local function floorAt(point: Vector3): (Instance?, string?)
	local hit = workspace:Raycast(
		point + Vector3.yAxis * Config.ProbeLift,
		-Vector3.yAxis * (Config.ProbeLift + Config.ProbeDepth),
		Params
	)
	if not hit then
		return nil, nil
	end

	local bakeries = World.Bakeries()
	local bakery: Instance = hit.Instance
	while bakery.Parent and bakery.Parent ~= bakeries do
		bakery = bakery.Parent
	end
	if not bakery.Parent then
		return nil, nil
	end

	for room, path in Config.Floors do
		local folder = Buildings.ResolvePath(bakery, path)
		if folder and hit.Instance:IsDescendantOf(folder) then
			return bakery, room
		end
	end
	return nil, nil
end

-- Room of a point within one bakery; anything not above that bakery's floors is Outside.
local function roomIn(bakery: Instance, point: Vector3): string
	local owner, room = floorAt(point)
	return if owner == bakery and room then room else Config.Outside
end

local function addEdge(edges: { Edge }, a: string, b: string, point: Vector3, door: Instance): ()
	for _, edge in edges do
		local same = (edge.a == a and edge.b == b) or (edge.a == b and edge.b == a)
		if same and (edge.point - point).Magnitude <= Config.MergeDistance then
			edge.count += 1
			edge.point = edge.point:Lerp(point, 1 / edge.count)
			return
		end
	end
	table.insert(edges, { a = a, b = b, point = point, door = door, count = 1 })
end

-- Doorways of a bakery and the two rooms each one joins, sampled on both sides of the leaf.
local function buildGraph(bakery: Instance): Graph
	local edges: { Edge } = {}
	local root = Buildings.ResolvePath(bakery, Config.DoorRoot)
	local candidates: { Instance } = if root then root:GetDescendants() else {}
	for _, door in candidates do
		if not door:IsA("Model") or door.Name:lower() ~= Config.DoorName then
			continue
		end

		local frame, size = door:GetBoundingBox()
		local center = frame.Position
		local pivot = door:GetPivot()
		for _, axis in { pivot.LookVector, pivot.RightVector } do
			local flat = Vector3.new(axis.X, 0, axis.Z)
			if flat.Magnitude < 1e-3 then
				continue
			end
			flat = flat.Unit * Config.SideDistance

			local front, back = roomIn(bakery, center + flat), roomIn(bakery, center - flat)
			if front ~= back then
				local aim = Vector3.new(center.X, center.Y - size.Y / 2 + Config.AimHeight, center.Z)
				addEdge(edges, front, back, aim, door)
				break
			end
		end
	end
	return { edges = edges, built = os.clock() }
end

local function graphFor(bakery: Instance): Graph
	local graph = Graphs[bakery]
	if graph and os.clock() - graph.built < Config.RefreshSeconds then
		return graph
	end
	local built = buildGraph(bakery)
	Graphs[bakery] = built
	return built
end

-- First doorway from one room toward another: fewest doorways, the nearest one on ties.
local function firstDoor(edges: { Edge }, from: string, to: string, origin: Vector3): Edge?
	local hops: { [string]: number } = { [to] = 0 }
	local frontier = { to }
	while #frontier > 0 and not hops[from] do
		local nextFrontier = {}
		for _, room in frontier do
			for _, edge in edges do
				local other = if edge.a == room then edge.b elseif edge.b == room then edge.a else nil
				if other and not hops[other] then
					hops[other] = hops[room] + 1
					table.insert(nextFrontier, other)
				end
			end
		end
		frontier = nextFrontier
	end

	local remaining = hops[from]
	if not remaining then
		return nil
	end

	local best: Edge?, bestDistance = nil, math.huge
	for _, edge in edges do
		local other = if edge.a == from then edge.b elseif edge.b == from then edge.a else nil
		if other and hops[other] == remaining - 1 then
			local distance = (edge.point - origin).Magnitude
			if distance < bestDistance then
				best, bestDistance = edge, distance
			end
		end
	end
	return best
end

--[[ Handling ]]--
--- The bakery room a point stands in, or nil when it is above no room's floor.
function HintRoute.Room(point: Vector3): string?
	refreshFloors()
	local _, room = floorAt(point)
	return room
end

--- Where guidance toward `target` should point right now: the target itself, or the first doorway
--- toward it with that doorway's model. Targets outside every room are never rerouted.
function HintRoute.Waypoint(target: Vector3): (Vector3, Instance?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return target, nil
	end

	refreshFloors()
	local bakery, goal = floorAt(target)
	if not bakery or not goal then
		return target, nil
	end

	local origin = root.Position
	local here = roomIn(bakery, origin)
	if here == goal then
		return target, nil
	end

	local edge = firstDoor(graphFor(bakery).edges, here, goal, origin)
	if not edge or not edge.door.Parent then
		return target, nil
	end
	return edge.point, edge.door
end

return HintRoute
