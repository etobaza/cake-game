--!strict
-- One Heartbeat for the whole gameplay: other systems hook onto Tick instead of running their own loops.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Libs = _Shared.Libs

--[[ Modules ]]--
local Signal = require(_Libs.Signal)

--[[ Constants ]]--
local TICK_INTERVAL = 1 / 10

--[[ Tables ]]--
local TickHandler = {
	-- Starts before the gameplay systems so they can subscribe before the first tick.
	priority = 100,
}

-- Fired at a fixed rate with the seconds actually elapsed since the previous tick.
TickHandler.Tick = Signal() :: Signal.Signal<number>

--[[ Handling ]]--
function TickHandler.OnInit(self: TickHandler): ()
	self.Accumulator = 0
end

function TickHandler.OnStart(self: TickHandler): ()
	RunService.Heartbeat:Connect(function(deltaTime: number)
		self.Accumulator += deltaTime
		if self.Accumulator < TICK_INTERVAL then
			return
		end

		local elapsed = self.Accumulator
		self.Accumulator = 0

		self.Tick:Fire(elapsed)
	end)
end

export type TickHandler = typeof(TickHandler) & {
	Accumulator: number,
}

return TickHandler :: TickHandler
