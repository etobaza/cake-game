--!strict
-- Server-owned longitudinal traffic. Distances never wrap, so snapshots interpolate safely.
local Config = require(script.Parent.Configs.Traffic)

export type Car = { Distance: number, Speed: number, Length: number, CruiseSpeed: number?, YellowPass: number? }
local Simulation = {}

function Simulation.Phase(elapsed: number): string
	local signals = Config.Signals
	local time = elapsed % (signals.GreenSeconds + signals.YellowSeconds + signals.RedSeconds)
	if time < signals.GreenSeconds then
		return "Green"
	end
	if time < signals.GreenSeconds + signals.YellowSeconds then
		return "Yellow"
	end
	return "Red"
end

function Simulation.Step(cars: { Car }, stops: { number }, length: number, elapsed: number, deltaTime: number): ()
	local phase = Simulation.Phase(elapsed)
	local startsYellow = phase == "Yellow" and Simulation.Phase(elapsed - deltaTime) == "Green"
	local nextStates: { { number } } = {}
	for index, car in cars do
		local front = car.Distance + car.Length / 2
		local stopGap = math.huge
		for _, stop in stops do
			local gap = (stop - Config.Signals.StopBuffer - front) % length
			if length - gap < 0.001 then
				gap = 0
			end
			stopGap = math.min(stopGap, gap)
		end
		local stopAt = front + stopGap
		if startsYellow then
			-- Cars already too close to brake clear the line during yellow; others prepare to stop.
			car.YellowPass = if stopGap < car.Speed * car.Speed / (2 * Config.Braking) + 2 then stopAt else nil
		elseif phase ~= "Yellow" then
			car.YellowPass = nil
		end
		local mustStop = phase == "Red"
			or (phase == "Yellow" and (not car.YellowPass or math.abs(car.YellowPass - stopAt) > 0.01))
		local allowed = if mustStop then stopGap else math.huge
		local desired = math.min(car.CruiseSpeed or Config.Speed, math.sqrt(2 * Config.Braking * allowed))
		if #cars > 1 then
			local leader = cars[index % #cars + 1]
			local gap = math.max(
				0,
				(leader.Distance - car.Distance) % length - (car.Length + leader.Length) / 2 - Config.QueueGap
			)
			allowed = math.min(allowed, gap)
			desired = math.min(desired, math.sqrt(leader.Speed * leader.Speed + 2 * Config.Braking * gap))
			-- Time headway spaces moving cars farther apart than a stationary signal queue.
			desired = math.min(desired, gap / Config.HeadwaySeconds)
		end
		local speed = if desired >= car.Speed
			then math.min(desired, car.Speed + Config.Acceleration * deltaTime)
			else math.max(desired, car.Speed - Config.Braking * deltaTime)
		local advance = (car.Speed + speed) * deltaTime / 2
		if advance >= allowed then
			advance = allowed
			speed = 0
		end
		nextStates[index] = { car.Distance + advance, speed }
	end
	for index, state in nextStates do
		cars[index].Distance = state[1]
		cars[index].Speed = state[2]
	end
end

return Simulation
