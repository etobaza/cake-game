--!strict
-- Which HUD groups the introduction has revealed so far. HydrateHud slides a group in from its edge
-- only while it is revealed (and no page covers the HUD); the client TutorialHandler decides.
--
-- Groups hold their first entrance until `Ready`, so a group the introduction hides never rides in
-- at spawn only to ride straight back out. If nothing decides in time, everything is revealed.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)

--[[ Constants ]]--
-- Seconds after load before the HUD enters anyway, when no decision arrives.
local READY_TIMEOUT = 5

--[[ Tables ]]--
local HudReveal = {}
local nodes: { [string]: Flux.Node<boolean> } = {}
local ready = Flux(false)

--[[ Private Functions ]]--
local function node(name: string): Flux.Node<boolean>
	local existing = nodes[name]
	if existing then
		return existing
	end
	local created = Flux(true)
	nodes[name] = created
	return created
end

--[[ Handling ]]--
--- True while `name` may be on screen. Read it inside a Flux effect to follow changes.
function HudReveal.Shown(name: string): boolean
	return ready() and node(name)()
end

function HudReveal.Set(name: string, shown: boolean): ()
	node(name):set(shown)
end

--- The first decision has been made; groups may now take their entrance.
function HudReveal.Ready(): ()
	ready:set(true)
end

task.delay(READY_TIMEOUT, HudReveal.Ready)

return HudReveal
