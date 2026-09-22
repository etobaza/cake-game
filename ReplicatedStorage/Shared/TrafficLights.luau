--!strict
-- Bind streamed authored lenses; their phase uses the same presentation time as the cars.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Configs.Traffic).Signals
local Janitor = require(ReplicatedStorage.Packages.janitor)

local Lights = {}

function Lights.new(): { SetPhase: (string) -> (), Destroy: () -> () }
	local janitor = Janitor.new()
	local lamps: { [BasePart]: { Role: string, Glow: PointLight } } = {}
	local phase = ""
	local function paint(part: BasePart, role: string, glow: PointLight): ()
		local active = role == phase
		part.Color = if active then Config.Colors[role] else Config.OffColor
		part.Material = if active then Enum.Material.Neon else Enum.Material.SmoothPlastic
		glow.Enabled = active
	end
	local function bind(instance: Instance): ()
		if not instance:IsA("BasePart") or lamps[instance] then
			return
		end
		local role = instance:GetAttribute("TrafficLamp")
		if typeof(role) ~= "string" or not Config.Colors[role] then
			return
		end
		local scope = Janitor.new()
		local color, material = instance.Color, instance.Material
		local glow = Instance.new("PointLight")
		glow.Name = "TrafficGlow"
		glow.Color = Config.Colors[role]
		glow.Brightness = 1.5
		glow.Range = 7
		glow.Shadows = false
		glow.Parent = instance
		scope:Add(glow, "Destroy")
		scope:Add(function(): ()
			lamps[instance] = nil
			if instance.Parent then
				instance.Color = color
				instance.Material = material
			end
		end, true)
		lamps[instance] = { Role = role, Glow = glow }
		janitor:Add(scope, "Destroy", instance)
		paint(instance, role, glow)
	end
	janitor:Add(CollectionService:GetInstanceAddedSignal(Config.LampTag):Connect(bind), "Disconnect")
	janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Config.LampTag):Connect(function(instance: Instance): ()
			janitor:Remove(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Config.LampTag) do
		bind(instance)
	end
	return {
		SetPhase = function(nextPhase: string): ()
			if phase == nextPhase then
				return
			end
			phase = nextPhase
			for part, lamp in lamps do
				paint(part, lamp.Role, lamp.Glow)
			end
		end,
		Destroy = function(): ()
			janitor:Destroy()
		end,
	}
end

return Lights
