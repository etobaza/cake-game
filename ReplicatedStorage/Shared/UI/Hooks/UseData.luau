--!strict
-- The bridge between the replicated player data and the reactive graph.
--
-- DataClient pushes changes through Signals; Flux wants nodes. These helpers wrap a path once and
-- register the disconnect with the surrounding scope, so a screen that is destroyed stops listening
-- without anyone remembering to unsubscribe.
--
-- Call these INSIDE a Flux.scope. Outside one the subscription has no owner and will leak.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)

--[[ Types ]]--
export type Path = { string | number }

--[[ Tables ]]--
local UseData = {}

--[[ Handling ]]--
--- A node holding the value at `path`, kept current for as long as the scope lives.
--- `kind` is "Cloud" (default) or "Session"; `default` stands in until the first snapshot arrives.
function UseData.Path<T>(client: any, path: Path, kind: string?, default: T): Flux.Node<T>
	local initial = client:GetData(path, kind)
	local node = Flux(if initial == nil then default else initial :: T)

	local connection = client:SubscribeToPath(path, function(value: any)
		node:set(if value == nil then default else value :: T)
	end, kind)

	Flux.cleanup(function()
		connection:Disconnect()
	end)

	return node
end

--- A node that re-reads `compute` whenever anything under `path` changes.
--- Use it when the value shown is derived from a subtree rather than one leaf.
function UseData.Derived<T>(client: any, path: Path, kind: string?, compute: () -> T): Flux.Node<T>
	local node = Flux(compute())

	local connection = client:SubscribeToPath(path, function()
		node:set(compute(), true)
	end, kind, true)

	Flux.cleanup(function()
		connection:Disconnect()
	end)

	return node
end

return UseData
