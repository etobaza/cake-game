--!strict
-- Local presentation of the cupcake rain. The server places every cupcake at its landing spot with
-- a `LandsAt` time; this module lifts it into the sky and drops it on schedule, then lets it spin
-- and bob until the server collects or expires it. Only the owner's cupcakes are drawn: anyone
-- else's cannot be collected by this player and would only mislead them.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)

--[[ Types ]]--
type Cupcake = { Model: Model, Rest: CFrame, LandsAt: number }

--[[ Tables ]]--
local Rain = {}
Rain.__index = Rain

--[[ Private Functions ]]--
local function hide(model: Model): ()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
		end
	end
end

--[[ Handling ]]--
function Rain.new(folder: Instance): Rain
	local self = setmetatable({ Cupcakes = {} :: { [Model]: Cupcake }, Connections = {} :: { RBXScriptConnection } }, Rain)

	local function track(instance: Instance): ()
		if not instance:IsA("Model") then
			return
		end
		local landsAt = instance:GetAttribute("LandsAt")
		if typeof(landsAt) ~= "number" then
			return
		end
		if instance:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
			hide(instance)
			return
		end
		self.Cupcakes[instance] = { Model = instance, Rest = instance:GetPivot(), LandsAt = landsAt }
	end

	for _, descendant in folder:GetDescendants() do
		track(descendant)
	end
	table.insert(self.Connections, folder.DescendantAdded:Connect(track))
	table.insert(
		self.Connections,
		RunService.RenderStepped:Connect(function(): ()
			self:Step(workspace:GetServerTimeNow())
		end)
	)
	return self
end

function Rain.Step(self: Rain, now: number): ()
	local tuning = Config.Rain
	for model, cupcake in self.Cupcakes do
		if not model.Parent then
			self.Cupcakes[model] = nil
			continue
		end
		local spin = CFrame.Angles(0, (now * tuning.SpinSpeed) % (math.pi * 2), 0)
		local remaining = cupcake.LandsAt - now
		local lift = if remaining > 0
			then tuning.DropHeight * (math.min(remaining / tuning.FallSeconds, 1) ^ 2)
			else tuning.BobHeight * (1 + math.sin(now * tuning.BobSpeed))
		model:PivotTo(cupcake.Rest * CFrame.new(0, lift, 0) * spin)
	end
end

function Rain.Destroy(self: Rain): ()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Cupcakes)
end

export type Rain = typeof(setmetatable(
	{} :: { Cupcakes: { [Model]: Cupcake }, Connections: { RBXScriptConnection } },
	Rain
))

return Rain
