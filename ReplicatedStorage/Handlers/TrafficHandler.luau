--!strict
-- Interpolate authoritative queues and show lamps at the exact same presentation time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Configs.Traffic)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Path = require(ReplicatedStorage.Shared.TrafficPath)
local Simulation = require(ReplicatedStorage.Shared.TrafficSimulation)
local Lights = require(ReplicatedStorage.Shared.TrafficLights)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "TrafficHandler" })

local TrafficHandler = {}
type Snapshot = { Time: number, Cars: { { number } } }

function TrafficHandler.OnInit(self: TrafficHandler): ()
	self.Janitor = Janitor.new()
end

function TrafficHandler.OnStart(self: TrafficHandler): ()
	if not Config.Enabled then
		return
	end
	local state = ReplicatedStorage:WaitForChild(Config.StateName, 10)
	local templates = state and state:WaitForChild("Vehicles", 10)
	if not state or not templates then
		Logger:Warn("Traffic templates are unavailable")
		return
	end
	local roadFrame, roadSize, startedAt =
		state:GetAttribute("RoadFrame"), state:GetAttribute("RoadSize"), state:GetAttribute("StartedAt")
	local count = state:GetAttribute("VehicleCount")
	if
		typeof(roadFrame) ~= "CFrame"
		or typeof(roadSize) ~= "Vector3"
		or typeof(startedAt) ~= "number"
		or typeof(count) ~= "number"
		or count < 1
	then
		Logger:Warn("Traffic route is incomplete")
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.VisualName
	self.Janitor:Add(folder, "Destroy")
	local vehicles: { { Car: BasePart, Path: Path.Path, Index: number } } = {}
	for index = 1, count do
		-- Named slots allow late replication without losing a variant or changing the shared order.
		local source = templates:WaitForChild(tostring(index), 10)
		if not source or not source:IsA("BasePart") then
			Logger:Warn(`Traffic variant {index} is unavailable`)
			continue
		end
		local car = source:Clone()
		local variantName = source:GetAttribute("VariantName")
		car.Name = if typeof(variantName) == "string" then variantName else source.Name
		car.Anchored = true
		car.CanCollide = false
		car.CanTouch = false
		car.CanQuery = false
		local path = Path.Build(roadFrame, roadSize, car.Size.Y)
		vehicles[#vehicles + 1] = { Car = car, Path = path, Index = index }
		car.Parent = folder
	end
	local lights = Lights.new()
	self.Janitor:Add(lights, "Destroy")
	local snapshots: { Snapshot } = {}
	local function receive(): ()
		local encoded = state:GetAttribute(Config.MotionAttribute)
		if typeof(encoded) ~= "string" then
			return
		end
		local snapshot: Snapshot = HttpService:JSONDecode(encoded)
		local previous = snapshots[#snapshots]
		if previous and snapshot.Time <= previous.Time then
			return
		end
		snapshots[#snapshots + 1] = snapshot
		while #snapshots > 16 do
			table.remove(snapshots, 1)
		end
	end
	self.Janitor:Add(state:GetAttributeChangedSignal(Config.MotionAttribute):Connect(receive), "Disconnect")
	receive()
	local function step(): ()
		local latest = snapshots[#snapshots]
		if not latest then
			return
		end
		-- Hold the latest complete state when packets stall; never extrapolate through a red light.
		local time =
			math.clamp(workspace:GetServerTimeNow() - Config.InterpolationDelay, snapshots[1].Time, latest.Time)
		local first, last = snapshots[1], latest
		for index = 2, #snapshots do
			if snapshots[index].Time >= time then
				first = snapshots[index - 1]
				last = snapshots[index]
				break
			end
		end
		local alpha = if last.Time > first.Time then (time - first.Time) / (last.Time - first.Time) else 0
		for _, vehicle in vehicles do
			local from, to = first.Cars[vehicle.Index], last.Cars[vehicle.Index]
			if from and to then
				vehicle.Car.CFrame = Path.Sample(vehicle.Path, from[1] + (to[1] - from[1]) * alpha)
			end
		end
		lights.SetPhase(Simulation.Phase(time - startedAt))
		if not folder.Parent then
			folder.Parent = workspace
		end
	end
	step()
	self.Janitor:Add(RunService.PreRender:Connect(step), "Disconnect")
	self.Janitor:Add(
		state.Destroying:Connect(function(): ()
			self:Destroy()
		end),
		"Disconnect"
	)
end

function TrafficHandler.Destroy(self: TrafficHandler): ()
	self.Janitor:Destroy()
end

export type TrafficHandler = typeof(TrafficHandler) & { Janitor: any }
return TrafficHandler :: TrafficHandler
