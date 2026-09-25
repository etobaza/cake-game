--!strict
-- Prepares the existing sink surface and owns its ambient droplets for the plot's lifetime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.Garden).SinkWater

local SinkWater = {}

function SinkWater.Prepare(bakery: Folder): ()
	local current: Instance? = bakery
	for _, name in Config.Path do
		current = if current then current:FindFirstChild(name) else nil
	end
	if not current or not current:IsA("BasePart") then
		print(`[SinkWater] Missing authored sink surface in {bakery.Name}`)
		return
	end

	local surface = current
	surface.Color = Config.Color
	surface.Material = Enum.Material.Glass
	surface.Transparency = Config.Transparency
	surface.Reflectance = Config.Reflectance
	surface.CanCollide = false
	surface.CanQuery = false
	surface.CanTouch = false

	-- The surface owns the attachment and emitter; repeated preparation creates no duplicates.
	local previous = surface:FindFirstChild("SinkTrickle")
	if previous then
		previous:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SinkTrickle"
	attachment.Position = Config.TrickleOffset
	attachment.Parent = surface

	local droplets = Instance.new("ParticleEmitter")
	droplets.Name = "Droplets"
	droplets.Texture = Config.Texture
	droplets.Color = ColorSequence.new(Config.Color, Color3.fromRGB(117, 243, 237))
	droplets.EmissionDirection = Enum.NormalId.Bottom
	droplets.Rate = Config.TrickleRate
	droplets.Lifetime = NumberRange.new(Config.TrickleLifetime)
	droplets.Speed = NumberRange.new(Config.TrickleSpeed)
	droplets.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, Config.TrickleSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	droplets.Transparency = NumberSequence.new(0, 1)
	droplets.Parent = attachment
end

return SinkWater
