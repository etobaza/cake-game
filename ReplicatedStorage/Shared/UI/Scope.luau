--!strict
-- Runs `fn` inside a fresh Flux scope and returns that scope, so a handler can hand it to its Janitor
-- ("Destroy") and tear down every binding created inside in one call.
--
-- Flux types the callback as `(scope) -> T`, which the solver cannot satisfy with a callback that
-- returns nothing; this is the single place that widens it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Flux = require(ReplicatedStorage.Packages.flux)

--[[ Tables ]]--
local Scope = {}

--[[ Handling ]]--
function Scope.Run(fn: () -> ()): Flux.Node<any>
	return (Flux.scope :: any)(fn)
end

return Scope
