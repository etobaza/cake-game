--!strict
-- The bakeries' fake sunbeams: unlit Beams on the authored Fx "RayPart" parts in the cafe and garden.
-- LightInfluence is 0, so they keep shining through the windows whatever Lighting.ClockTime says;
-- the evening lighting switches them off. Client presentation only. Bakeries may stream in late, so
-- beams are tracked as they arrive, and each keeps its authored Enabled for when the day returns.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local DayCycleConfig = require(ReplicatedStorage.Shared.Configs.DayCycle)
local World = require(ReplicatedStorage.Shared.World)

--[[ Tables ]]--
local Sunbeams = {}
Sunbeams.__index = Sunbeams

export type Sunbeams = typeof(setmetatable(
	{} :: {
		-- Each tracked beam's authored Enabled.
		Beams: { [Beam]: boolean },
		Evening: boolean,
		Connections: { RBXScriptConnection },
		Alive: boolean,
	},
	Sunbeams
))

local function isSunbeam(instance: Instance): boolean
	local parent = instance.Parent
	return instance:IsA("Beam") and parent ~= nil and parent.Name == DayCycleConfig.SunbeamPartName
end

function Sunbeams.new(): Sunbeams
	local self = setmetatable({
		Beams = {},
		Evening = false,
		Connections = {},
		Alive = true,
	}, Sunbeams)
	task.spawn(function()
		local bakeries = World.WaitForBakeries()
		if not self.Alive then
			return
		end
		table.insert(
			self.Connections,
			bakeries.DescendantAdded:Connect(function(instance: Instance)
				self:Track(instance)
			end)
		)
		table.insert(
			self.Connections,
			bakeries.DescendantRemoving:Connect(function(instance: Instance)
				if instance:IsA("Beam") then
					self.Beams[instance] = nil
				end
			end)
		)
		for _, instance in bakeries:GetDescendants() do
			self:Track(instance)
		end
	end)
	return self
end

function Sunbeams.Track(self: Sunbeams, instance: Instance): ()
	if not isSunbeam(instance) then
		return
	end
	local beam = instance :: Beam
	if self.Beams[beam] == nil then
		self.Beams[beam] = beam.Enabled
	end
	beam.Enabled = self.Beams[beam] and not self.Evening
end

function Sunbeams.SetEvening(self: Sunbeams, evening: boolean): ()
	if self.Evening == evening then
		return
	end
	self.Evening = evening
	for beam, authored in self.Beams do
		beam.Enabled = authored and not evening
	end
end

function Sunbeams.Destroy(self: Sunbeams): ()
	self.Alive = false
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for beam, authored in self.Beams do
		beam.Enabled = authored
	end
	table.clear(self.Beams)
end

return Sunbeams
