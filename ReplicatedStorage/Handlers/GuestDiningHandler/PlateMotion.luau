--!strict
-- Authored cutlery follows both hands while the fork moves from the guest's plate to their mouth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.GuestDining)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local PlateArm = require(script.Parent.PlateArm)

local PlateMotion = {}
PlateMotion.__index = PlateMotion

export type PlateMotion = typeof(setmetatable(
	{} :: {
		Model: Model,
		Head: BasePart,
		Hand: BasePart,
		LeftHand: BasePart,
		Torso: BasePart,
		TargetFrame: CFrame,
		KnifeTargetFrame: CFrame,
		Arm: PlateArm.PlateArm,
		LeftArm: PlateArm.PlateArm,
		Active: boolean,
		Fork: Model,
		Knife: Model,
		Janitor: any,
	},
	PlateMotion
))

local function smooth(value: number): number
	local alpha = math.clamp(value, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function cloneUtensil(name: string, scale: number): (Model?, CFrame?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local folder = models and models:FindFirstChild(Config.Plate.CutleryFolder)
	local template = folder and folder:FindFirstChild(name)

	if not template or not template:IsA("Model") then
		return nil, nil
	end

	local utensil = template:Clone()
	utensil.Name = "Dining" .. name
	utensil:ScaleTo(scale)

	local tip = utensil:FindFirstChild("Tip", true)
	if not tip or not tip:IsA("Attachment") then
		utensil:Destroy()
		return nil, nil
	end

	return utensil, utensil:GetPivot():ToObjectSpace(tip.WorldCFrame)
end

function PlateMotion.new(model: Model): PlateMotion?
	local head = model:FindFirstChild("Head")
	local hand = model:FindFirstChild("RightHand")
	local leftHand = model:FindFirstChild("LeftHand")
	local arm = model:FindFirstChild("RightUpperArm")
	local leftArm = model:FindFirstChild("LeftUpperArm")
	local torso = model:FindFirstChild("UpperTorso")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local position = model:GetAttribute(Config.PlateAttribute)

	if
		not head
		or not head:IsA("BasePart")
		or not hand
		or not hand:IsA("BasePart")
		or not leftHand
		or not leftHand:IsA("BasePart")
		or not arm
		or not arm:IsA("BasePart")
		or not leftArm
		or not leftArm:IsA("BasePart")
		or not torso
		or not torso:IsA("BasePart")
		or not humanoid
		or typeof(position) ~= "Vector3"
	then
		return nil
	end

	local settings = Config.Plate
	local fork, forkTip = cloneUtensil("Fork", settings.Fork.Scale)
	local knife, knifeTip = cloneUtensil("Knife", settings.Knife.Scale)

	if not fork or not forkTip or not knife or not knifeTip then
		if fork then
			fork:Destroy()
		end
		if knife then
			knife:Destroy()
		end
		return nil
	end

	local janitor = Janitor.new()
	janitor:Add(fork, "Destroy")
	janitor:Add(knife, "Destroy")

	local armPose = PlateArm.new(model, torso, "Right", settings.Fork.Grip * forkTip, settings.Fork.ElbowDirection)
	local leftPose = PlateArm.new(model, torso, "Left", settings.Knife.Grip * knifeTip, settings.Knife.ElbowDirection)
	janitor:Add(armPose, "Destroy")
	janitor:Add(leftPose, "Destroy")

	return setmetatable({
		Model = model,
		Head = head,
		Hand = hand,
		LeftHand = leftHand,
		Torso = torso,
		TargetFrame = CFrame.new(position),
		KnifeTargetFrame = CFrame.new(position),
		Arm = armPose,
		LeftArm = leftPose,
		Active = false,
		Fork = fork,
		Knife = knife,
		Janitor = janitor,
	}, PlateMotion)
end

function PlateMotion.Step(self: PlateMotion, now: number, started: number, ends: number): ()
	local position = self.Model:GetAttribute(Config.PlateAttribute)

	if typeof(position) ~= "Vector3" then
		self.Active = false
		return
	end

	local settings = Config.Plate
	local phase = (math.max(0, now - started) / settings.CycleSeconds) % 1
	local plate = position + settings.SurfaceOffset
	local mouth = self.Head.CFrame:PointToWorldSpace(settings.MouthOffset)
	local towardGuest = (self.Torso.Position - plate) * Vector3.new(1, 0, 1)

	if towardGuest.Magnitude > 0.001 then
		plate += towardGuest.Unit * settings.NearEdgeOffset
	end

	local alpha = 0
	local cut = 0

	if phase < settings.ScoopEnd then
		local scoop = math.sin(math.pi * phase / settings.ScoopEnd) ^ 2
		plate += self.Head.CFrame.RightVector * settings.ScoopDistance * scoop
		cut = math.sin(2 * math.pi * phase / settings.ScoopEnd) * scoop
	elseif phase < settings.LiftEnd then
		alpha = smooth((phase - settings.ScoopEnd) / (settings.LiftEnd - settings.ScoopEnd))
	elseif phase < settings.BiteEnd then
		alpha = 1
	elseif phase < settings.ReturnEnd then
		alpha = 1 - smooth((phase - settings.BiteEnd) / (settings.ReturnEnd - settings.BiteEnd))
	end

	local target = plate:Lerp(mouth, alpha) + Vector3.yAxis * math.sin(alpha * math.pi) * settings.ArcHeight
	self.TargetFrame = CFrame.new(target) * self.Torso.CFrame.Rotation * CFrame.Angles(0, settings.ForkTurn * alpha, 0)

	local knife = settings.Knife
	local knifePosition = plate + self.Torso.CFrame:VectorToWorldSpace(knife.PlateOffset)
	knifePosition += self.Torso.CFrame.LookVector * cut * knife.CutDistance
	knifePosition += Vector3.yAxis * alpha * knife.RestHeight
	self.KnifeTargetFrame = CFrame.new(knifePosition) * self.Torso.CFrame.Rotation * CFrame.Angles(0, 0, knife.Roll)
	self.Active = now < ends - Config.PoseFadeSeconds
end

function PlateMotion.Restore(self: PlateMotion): ()
	self.Arm:Restore()
	self.LeftArm:Restore()
end

function PlateMotion.Animate(self: PlateMotion, deltaTime: number): ()
	self.Arm:Step(deltaTime, self.Active, self.TargetFrame)
	self.LeftArm:Step(deltaTime, self.Active, self.KnifeTargetFrame)
end

function PlateMotion.Align(self: PlateMotion): ()
	self.Fork:PivotTo(self.Hand.CFrame * Config.Plate.Fork.Grip)
	self.Knife:PivotTo(self.LeftHand.CFrame * Config.Plate.Knife.Grip)
	self.Fork.Parent = self.Model
	self.Knife.Parent = self.Model
end

function PlateMotion.Destroy(self: PlateMotion): ()
	self.Janitor:Destroy()
end

return PlateMotion
