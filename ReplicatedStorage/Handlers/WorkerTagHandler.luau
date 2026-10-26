--!strict
-- Slides the holographic gradient on paid workers' name tags (Configs/Workers.Tag).
--
-- The server builds each tag with a still gradient; colour changes every frame would flood
-- replication, so each client moves the hues itself. Every UIGradient named Tag.HoloName under the
-- Workers folder is tracked: on a TextLabel it takes the text's colours, on the glow behind it the
-- deeper, trailing ones.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Workers)

--[[ Constants ]]--
-- Colour steps per second; the hues move slowly, so this reads as smooth.
local STEP_SECONDS = 1 / 30

--[[ Tables ]]--
local WorkerTagHandler = {}

--[[ Handling ]]--
function WorkerTagHandler.OnStart(self: WorkerTagHandler): ()
	self.Gradients = {}
	self.NextStep = 0

	task.spawn(function()
		local folder = workspace:WaitForChild(Config.FolderName)
		folder.DescendantAdded:Connect(function(descendant: Instance)
			self:Track(descendant)
		end)
		folder.DescendantRemoving:Connect(function(descendant: Instance)
			if descendant:IsA("UIGradient") then
				self.Gradients[descendant] = nil
			end
		end)
		for _, descendant in folder:GetDescendants() do
			self:Track(descendant)
		end
	end)

	RunService.PreRender:Connect(function()
		self:Step()
	end)
end

function WorkerTagHandler.Track(self: WorkerTagHandler, instance: Instance): ()
	if instance:IsA("UIGradient") and instance.Name == Config.Tag.HoloName then
		self.Gradients[instance] = instance.Parent ~= nil and instance.Parent:IsA("ImageLabel")
	end
end

function WorkerTagHandler.Step(self: WorkerTagHandler): ()
	local clock = os.clock()
	if clock < self.NextStep or next(self.Gradients) == nil then
		return
	end
	self.NextStep = clock + STEP_SECONDS

	local holo = Config.Tag.Holo
	local phase = clock * holo.Speed
	local text = Config.HoloColors(phase, holo.Saturation)
	local glow = Config.HoloColors(phase - holo.GlowLag, holo.GlowSaturation)
	for gradient, isGlow in self.Gradients do
		gradient.Color = if isGlow then glow else text
	end
end

export type WorkerTagHandler = typeof(WorkerTagHandler) & {
	-- Each tracked gradient, true when it tints the glow rather than the text.
	Gradients: { [UIGradient]: boolean },
	NextStep: number,
}

return WorkerTagHandler :: WorkerTagHandler
