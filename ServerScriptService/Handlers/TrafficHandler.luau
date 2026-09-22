--!strict
-- Publish the imported vehicle variants and route once; clients own smooth decorative motion.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Configs.Traffic)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Path = require(ReplicatedStorage.Shared.TrafficPath)
local Simulation = require(ReplicatedStorage.Shared.TrafficSimulation)
local TickHandler = require(script.Parent.TickHandler)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "TrafficHandler" })

local TrafficHandler = { dependencies = { "TickHandler" } }

local function find(path: { string }): Instance?
	local current: Instance? = workspace
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function signals(janitor: any, road: BasePart, path: Path.Path): { number }
	local stops: { number } = {}
	local folder = find(Config.Signals.Path)
	if not folder then
		Logger:Warn("Traffic signal folder is missing")
		return stops
	end
	local lines = Instance.new("Folder")
	lines.Name = "TrafficStopLines"
	lines.Parent = workspace
	janitor:Add(lines, "Destroy")
	for _, head in folder:GetChildren() do
		if not head:IsA("BasePart") or head.Name ~= Config.Signals.HeadName then
			continue
		end
		local lamps: { BasePart } = {}
		for _, child in head:GetChildren() do
			if child:IsA("BasePart") then
				lamps[#lamps + 1] = child
			end
		end
		if #lamps ~= 3 then
			continue
		end
		table.sort(lamps, function(a, b)
			return a.Position.Y > b.Position.Y
		end)
		for index, lamp in lamps do
			local previous = lamp:GetAttribute("TrafficLamp")
			lamp:SetAttribute("TrafficLamp", ({ "Red", "Yellow", "Green" })[index])
			lamp:AddTag(Config.Signals.LampTag)
			janitor:Add(function(): ()
				lamp:RemoveTag(Config.Signals.LampTag)
				lamp:SetAttribute("TrafficLamp", previous)
			end, true)
		end
		local localHead = road.CFrame:PointToObjectSpace(lamps[1].Position)
		local side = if localHead.X > 0 then 1 else -1
		local direction = if Config.Reverse then -side else side
		local z = localHead.Z - direction * Config.Signals.StopBeforeHead
		local stop = Vector3.new(side * path.Radius, 0, z)
		stops[#stops + 1] = Path.StopDistance(path, stop)
		local line = Instance.new("Part")
		line.Name = `StopLine{#stops}`
		line.Size = Vector3.new(road.Size.X / 2 - 2, 0.04, 1)
		line.CFrame = road.CFrame * CFrame.new(stop.X, road.Size.Y / 2 + 0.025, stop.Z)
		line.Color = Color3.fromRGB(245, 244, 228)
		line.Material = Enum.Material.SmoothPlastic
		line.Anchored, line.CanCollide, line.CanTouch, line.CanQuery = true, false, false, false
		line.Parent = lines
	end
	if #stops == 0 then
		Logger:Warn("No complete traffic lights found")
	end
	return stops
end

function TrafficHandler.OnInit(self: TrafficHandler): ()
	self.Janitor = Janitor.new()
end

function TrafficHandler.OnStart(self: TrafficHandler): ()
	if not Config.Enabled then
		return
	end
	local road, source = find(Config.RoadPath), find(Config.SourcePath)
	if not road or not road:IsA("BasePart") or not source then
		Logger:Warn("Authored road or vehicle pack is missing; traffic was not started")
		return
	end
	local vehicles: { BasePart } = {}
	for _, child in source:GetChildren() do
		if child:IsA("MeshPart") then
			vehicles[#vehicles + 1] = child
		end
	end
	if #vehicles == 0 then
		Logger:Warn("Vehicle pack contains no meshes")
		return
	end
	-- Publish every variant, then use a sparse random subset for this server's moving traffic.
	table.sort(vehicles, function(a, b)
		return a.Name < b.Name
	end)
	local random = Random.new()
	for index = #vehicles, 2, -1 do
		local other = random:NextInteger(1, index)
		vehicles[index], vehicles[other] = vehicles[other], vehicles[index]
	end
	local state = Instance.new("Folder")
	state.Name = Config.StateName
	self.Janitor:Add(state, "Destroy")
	local templates = Instance.new("Folder")
	templates.Name = "Vehicles"
	templates.Parent = state
	for index, vehicle in vehicles do
		local template = vehicle:Clone()
		template.Name = tostring(index)
		template:SetAttribute("VariantName", vehicle.Name)
		for _, child in template:GetDescendants() do
			if child:IsA("BaseScript") then
				child:Destroy()
			end
		end
		template.Anchored = true
		template.CanCollide = false
		template.CanTouch = false
		template.CanQuery = false
		template.CFrame = CFrame.identity
		template.Parent = templates
	end
	while #vehicles > Config.MaxActiveVehicles do
		table.remove(vehicles)
	end
	state:SetAttribute("VehicleCount", #vehicles)
	state:SetAttribute("RoadFrame", road.CFrame)
	state:SetAttribute("RoadSize", road.Size)
	local startedAt = workspace:GetServerTimeNow()
	state:SetAttribute("StartedAt", startedAt)
	local path = Path.Build(road.CFrame, road.Size, 0)
	local stops = signals(self.Janitor, road, path)
	state:SetAttribute("StopDistances", HttpService:JSONEncode(stops))
	local cars: { Simulation.Car } = {}
	local weights, totalWeight, occupied = {}, 0, 0
	for index, vehicle in vehicles do
		weights[index] = random:NextNumber(0.35, 1.8)
		totalWeight += weights[index]
		occupied += vehicle.Size.X + Config.QueueGap
	end
	local freeSpace = math.max(0, path.Length - occupied)
	local distance = Config.StartDistance
	for index, vehicle in vehicles do
		local cruise = Config.Speed * random:NextNumber(1 - Config.SpeedVariation, 1 + Config.SpeedVariation)
		cars[index] = {
			Distance = distance,
			Speed = 0,
			CruiseSpeed = cruise,
			Length = vehicle.Size.X,
			YellowPass = nil,
		}
		local nextVehicle = vehicles[index % #vehicles + 1]
		distance += (vehicle.Size.X + nextVehicle.Size.X) / 2 + Config.QueueGap + freeSpace * weights[index] / totalWeight
	end
	local simulatedAt = startedAt
	local function publish(): ()
		local positions = {}
		for index, car in cars do
			positions[index] = { car.Distance, car.Speed }
		end
		local phase = Simulation.Phase(simulatedAt - startedAt)
		state:SetAttribute("SignalPhase", phase)
		state:SetAttribute(Config.MotionAttribute, HttpService:JSONEncode({ Time = simulatedAt, Cars = positions }))
	end
	publish()
	state.Parent = ReplicatedStorage
	self.Janitor:Add(
		TickHandler.Tick:Connect(function(): ()
			local now = workspace:GetServerTimeNow()
			while simulatedAt + Config.SimulationStep <= now do
				simulatedAt += Config.SimulationStep
				Simulation.Step(cars, stops, path.Length, simulatedAt - startedAt, Config.SimulationStep)
			end
			publish()
		end),
		"Disconnect"
	)
end

function TrafficHandler.Destroy(self: TrafficHandler): ()
	self.Janitor:Destroy()
end

export type TrafficHandler = typeof(TrafficHandler) & { Janitor: any }
return TrafficHandler :: TrafficHandler
