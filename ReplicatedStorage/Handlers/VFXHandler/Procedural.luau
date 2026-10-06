--!strict
-- Builds burst templates from `Configs/VFX.Procedural` in the shape `Effect.new` expects from an
-- authored VFX part: emitters under attachments, `EmitCount` / `EmitDelay` attributes, disabled.
--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.VFX)

--[[ Tables ]]--
local Procedural = {}

--[[ Private Functions ]]--
local function findEmitter(folder: Instance?, path: string): ParticleEmitter?
	local current: Instance? = folder
	for _, name in string.split(path, "/") do
		current = if current then current:FindFirstChild(name) else nil
	end
	return if current and current:IsA("ParticleEmitter") then current else nil
end

local function apply(emitter: ParticleEmitter, spec: Config.EmitterSpec): ()
	if spec.Texture then
		emitter.Texture = spec.Texture
	end
	if spec.Color then
		emitter.Color = spec.Color
	end
	if spec.Size then
		emitter.Size = spec.Size
	end
	if spec.Transparency then
		emitter.Transparency = spec.Transparency
	end
	if spec.Squash then
		emitter.Squash = spec.Squash
	end
	if spec.Lifetime then
		emitter.Lifetime = spec.Lifetime
	end
	if spec.Speed then
		emitter.Speed = spec.Speed
	end
	if spec.Rotation then
		emitter.Rotation = spec.Rotation
	end
	if spec.RotSpeed then
		emitter.RotSpeed = spec.RotSpeed
	end
	if spec.SpreadAngle then
		emitter.SpreadAngle = spec.SpreadAngle
	end
	if spec.Acceleration then
		emitter.Acceleration = spec.Acceleration
	end
	if spec.Drag then
		emitter.Drag = spec.Drag
	end
	if spec.LightEmission then
		emitter.LightEmission = spec.LightEmission
	end
	if spec.LightInfluence then
		emitter.LightInfluence = spec.LightInfluence
	end
	if spec.Brightness then
		emitter.Brightness = spec.Brightness
	end
	if spec.ZOffset then
		emitter.ZOffset = spec.ZOffset
	end
	if spec.EmissionDirection then
		emitter.EmissionDirection = spec.EmissionDirection
	end
	if spec.Shape then
		emitter.Shape = spec.Shape
	end
	if spec.ShapeStyle then
		emitter.ShapeStyle = spec.ShapeStyle
	end
	if spec.ShapeInOut then
		emitter.ShapeInOut = spec.ShapeInOut
	end
	-- Bursts are emitted explicitly; a copied authored rate must not run on its own.
	emitter.Enabled = false
	emitter.Rate = 0
	emitter:SetAttribute("EmitCount", spec.Count)
	emitter:SetAttribute("EmitDelay", spec.Delay or 0)
end

--[[ Handling ]]--
--- A detached template part for `name`. `folder` is `Assets.VFX`, the source of `From` emitters.
function Procedural.Build(name: string, definition: Config.ProceduralEffect, folder: Instance?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = definition.Size or Vector3.one
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false

	for index, spec in definition.Emitters do
		local source = if spec.From then findEmitter(folder, spec.From) else nil
		if spec.From and not source then
			print(`[VFXHandler] {name}: missing source emitter {spec.From}`)
		end
		local emitter = if source then source:Clone() else Instance.new("ParticleEmitter")
		emitter.Name = `{spec.Name}{index}`
		apply(emitter, spec)
		if spec.OnPart then
			emitter.Parent = part
			continue
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = emitter.Name
		attachment.Position = spec.Offset or Vector3.zero
		attachment.Parent = part
		emitter.Parent = attachment
	end

	return part
end

return Procedural
