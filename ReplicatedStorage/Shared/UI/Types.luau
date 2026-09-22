--!strict
-- Prop types shared by every UI module.
--
-- Reactive<T> is the contract that makes a component work with both static and live values: pass a
-- plain T and the property is set once, pass a Flux node or a function of nodes and it follows.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)

--[[ Tables ]]--
local Types = {}

export type Reactive<T> = T | Flux.Node<T> | () -> T

return Types
