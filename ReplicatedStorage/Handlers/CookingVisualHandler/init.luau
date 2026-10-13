--!strict
-- Client handler that drives every cooking/entrance motion visual from one owned PreRender callback.
-- It tracks only Workspace descendants carrying the four CollectionService tags, routes each to its
-- private visual module, culls by camera distance, and tears each entry down (restoring the source)
-- on streaming removal, tag removal or handler teardown. It needs no DataClient and opens no
-- per-object connection or task.

--[[ Services ]]
--
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

--[[ References ]]
--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]
--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local CookingMotion = require(_Shared.Configs.CookingMotion)
local Util = require(_Shared.CookingMotionUtil)
local Mixer = require(script.Mixer)
local Clock = require(script.Clock)
local Entrance = require(script.Entrance)
local FreshFood = require(script.FreshFood)
local Pages = require(_Shared.UI.Stores.Pages)

--[[ Types ]]
--
type Entry = Util.VisualEntry

--[[ Constants ]]
--
-- Tag -> factory. Each factory validates the instance class before building an entry.
local FACTORIES: { [string]: (Instance) -> Entry? } = {
	[CookingMotion.SurfaceTag] = function(instance: Instance): Entry?
		return if instance:IsA("Folder") then Mixer.new(instance) else nil
	end,
	[CookingMotion.ClockTag] = function(instance: Instance): Entry?
		return if instance:IsA("BasePart") then Clock.new(instance) else nil
	end,
	[CookingMotion.EntranceTag] = function(instance: Instance): Entry?
		return if instance:IsA("Model") then Entrance.new(instance) else nil
	end,
	[CookingMotion.FreshTag] = function(instance: Instance): Entry?
		return if instance:IsA("Model") then FreshFood.new(instance) else nil
	end,
}

--[[ Tables ]]
--
local CookingVisualHandler = {
	dependencies = {},
	priority = 0,
	presenting = false,
	entries = {} :: { [Instance]: Entry },
	janitor = nil :: any,
}

--[[ Tracking ]]
--
function CookingVisualHandler.Track(self: CookingVisualHandler, instance: Instance, tag: string): ()
	-- Never track templates or inventory/Viewport copies; only live world objects animate.
	if self.entries[instance] ~= nil or not instance:IsDescendantOf(Workspace) then
		return
	end
	local factory = FACTORIES[tag]
	local entry = factory and factory(instance)
	if entry then
		self.entries[instance] = entry
	end
end

function CookingVisualHandler.Untrack(self: CookingVisualHandler, instance: Instance): ()
	local entry = self.entries[instance]
	if entry then
		self.entries[instance] = nil
		entry.Destroy()
	end
end

--[[ Presentation ]]
--
-- Integration seam: the Pages presenting owner (upgrade reveal) sets this so short celebrations and
-- mixing release their source masks while the camera presents; the entrance and clock keep their
-- authoritative pose regardless. No networking or schema state is introduced.
function CookingVisualHandler.SetPresenting(self: CookingVisualHandler, value: boolean): ()
	self.presenting = value
end

--[[ Scheduler ]]
--
function CookingVisualHandler.Step(self: CookingVisualHandler, dt: number): ()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraPosition = camera.CFrame.Position
	local now = Util.ServerNow()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local presenting = self.presenting or Pages.Presenting:peek() or humanoid == nil or humanoid.Health <= 0

	-- Removing the current key during traversal is safe, but defer it to keep the loop obvious.
	local dead: { Instance } = {}
	local context: Util.StepContext = {
		Now = now,
		Dt = dt,
		CameraPosition = cameraPosition,
		Presenting = presenting,
		Culled = false,
	}

	for instance, entry in self.entries do
		if not instance:IsDescendantOf(Workspace) then
			table.insert(dead, instance)
			continue
		end

		local focusPoint = entry.Focus()
		context.Culled = focusPoint ~= nil and (focusPoint - cameraPosition).Magnitude > CookingMotion.CullDistance
		entry.Step(context)
	end

	for _, instance in dead do
		self:Untrack(instance)
	end
end

--[[ Lifecycle ]]
--
function CookingVisualHandler.OnInit(self: CookingVisualHandler): ()
	self.janitor = Janitor.new()
	self.entries = {}
end

function CookingVisualHandler.OnStart(self: CookingVisualHandler): ()
	local janitor = self.janitor

	for tag in FACTORIES do
		janitor:Add(
			CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance): ()
				self:Track(instance, tag)
			end),
			"Disconnect"
		)
		janitor:Add(
			CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance): ()
				self:Untrack(instance)
			end),
			"Disconnect"
		)
		for _, instance in CollectionService:GetTagged(tag) do
			self:Track(instance, tag)
		end
	end

	-- The single owned callback for every entry; teardown disconnects it and destroys all entries.
	janitor:Add(
		RunService.PreRender:Connect(function(dt: number): ()
			self:Step(dt)
		end),
		"Disconnect"
	)
	janitor:Add(function(): ()
		for instance in self.entries do
			self:Untrack(instance)
		end
	end, true)
end

function CookingVisualHandler.Destroy(self: CookingVisualHandler): ()
	local janitor = self.janitor
	if janitor == nil then
		return
	end
	-- Janitor removes its metatable on destruction; release the owner before repeated cleanup.
	self.janitor = nil
	janitor:Destroy()
end

export type CookingVisualHandler = typeof(CookingVisualHandler)

return CookingVisualHandler
