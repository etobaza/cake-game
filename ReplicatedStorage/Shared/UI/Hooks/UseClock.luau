--!strict
-- A node that carries the current server time and updates on a slow tick.
--
-- Countdowns need to re-render without anything changing in the data -- nothing pushes "a second
-- passed". This is the one place a UI module is allowed its own Heartbeat, and it is shared: one
-- connection feeds every countdown on screen.
--
-- Call inside a Flux.scope; the connection is registered with it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)

--[[ Constants ]]--
-- Four times a second: fast enough that a seconds counter never visibly stalls, slow enough to be free.
local DEFAULT_INTERVAL = 0.25

--[[ Tables ]]--
local UseClock = {}

--[[ Handling ]]--
--- A node holding `workspace:GetServerTimeNow()`, refreshed every `interval` seconds.
function UseClock.Now(interval: number?): Flux.Node<number>
	local step = interval or DEFAULT_INTERVAL
	local node = Flux(workspace:GetServerTimeNow())
	local accumulated = 0

	local connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulated += deltaTime
		if accumulated < step then
			return
		end

		accumulated = 0
		node:set(workspace:GetServerTimeNow())
	end)

	Flux.cleanup(function()
		connection:Disconnect()
	end)

	return node
end

return UseClock
