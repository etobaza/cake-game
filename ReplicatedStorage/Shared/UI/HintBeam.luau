--!strict
-- One hint owns a local copy of the authored arrow beam and both of its endpoints.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.Hint)

local HintBeam = {}
HintBeam.__index = HintBeam
export type View = typeof(setmetatable(
	{} :: {
		Part: BasePart?,
		Beam: Beam?,
		Start: Attachment?,
		Finish: Attachment?,
		TextureStuds: number,
		LastLookup: number,
		Warned: boolean,
	},
	HintBeam
))

local function prepare(self: View): boolean
	if self.Part and self.Part.Parent then
		return true
	end
	-- Late asset replication must not stall the render callback.
	if os.clock() - self.LastLookup < Config.Beam.RetryInterval then
		return false
	end
	self.LastLookup = os.clock()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local template = vfx and vfx:FindFirstChild(Config.Beam.Template)
	if not template or not template:IsA("BasePart") then
		if not self.Warned then
			print("[HintBeam] ReplicatedStorage.Assets.VFX.ArrowBeam is missing")
			self.Warned = true
		end
		return false
	end

	local part = template:Clone()
	local beam = part:FindFirstChildWhichIsA("Beam")
	local first = beam and beam.Attachment0
	local last = beam and beam.Attachment1
	if
		not beam
		or not first
		or not last
		or first == last
		or not first:IsDescendantOf(part)
		or not last:IsDescendantOf(part)
	then
		part:Destroy()
		if not self.Warned then
			print("[HintBeam] ArrowBeam needs two distinct internal attachments")
			self.Warned = true
		end
		return false
	end
	self.Warned = false
	self.TextureStuds = math.max(
		Config.Beam.MinTextureSpacing,
		(first.WorldPosition - last.WorldPosition).Magnitude
			/ math.max(Config.Beam.MinTextureLength, beam.TextureLength)
	)
	part.Name = "HintArrowBeam"
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Transparency = 1
	beam.Enabled = false
	-- Preserve the scrolling direction, so arrows travel from player toward goal.
	self.Start = if beam.TextureSpeed < 0 then last else first
	self.Finish = if beam.TextureSpeed < 0 then first else last
	self.Part, self.Beam = part, beam
	part.Parent = workspace
	return true
end

function HintBeam.new(): View
	return setmetatable({ TextureStuds = 1, LastLookup = -math.huge, Warned = false }, HintBeam) :: View
end

function HintBeam.Hide(self: View): ()
	if self.Beam then
		self.Beam.Enabled = false
	end
end

function HintBeam.Show(self: View, point: Vector3): ()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		self:Hide()
		return
	end

	local origin = root.Position + Config.Beam.PlayerOffset
	local distance = (point - origin).Magnitude
	if distance < Config.Beam.MinDistance then
		self:Hide()
		return
	end

	if not prepare(self) then
		return
	end

	local part, beam, first, last = self.Part, self.Beam, self.Start, self.Finish
	if not part or not beam or not first or not last then
		return
	end
	part.CFrame = CFrame.new(origin)
	first.WorldPosition = origin
	last.WorldPosition = point
	-- Stretch counts repetitions; keep authored spacing as player-to-goal distance changes.
	if beam.TextureMode == Enum.TextureMode.Stretch then
		beam.TextureLength = math.max(Config.Beam.MinTextureLength, distance / self.TextureStuds)
	end
	beam.Enabled = true
end

function HintBeam.Destroy(self: View): ()
	if self.Part then
		self.Part:Destroy()
	end
	self.Part, self.Beam, self.Start, self.Finish = nil, nil, nil, nil
end

return HintBeam
