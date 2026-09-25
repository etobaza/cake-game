--!strict
-- Drives one oven's authored doors, clock hand and fuel prop from its server-owned station state.
-- It owns no cooking state: releasing the bakery restores every part to the artist's open pose.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local BaseHandler = require(ServerScriptService.Handlers.BaseHandler)
local CarryConfig = require(_Configs.CarryPresentation)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local LoggerUtil = require(_Shared.Libs.Logger)
local Motion = require(_Configs.OvenMotion)
local OvenFuel = require(_Configs.OvenFuel)
local OvenDial = require(script.Parent.OvenDial)

--[[ Constants ]]--
local FULL_TURN = math.pi * 2

local LEFT_DOOR_NAME = "OvenDoorLeft"
local RIGHT_DOOR_NAME = "OvenDoorRight"
local CLOCK_HAND_NAME = "ClockHand"
local BODY_NAME = "Oven"

-- Purchase order and artist slot order differ: Upgrade2 is oven_2 and Upgrade1 is oven_3.
local MODEL_PATHS = {
	[1] = { "1ndFloor", "Kitchen", "Decoration", "Oven" },
	[2] = { "1ndFloor", "Kitchen", "Upgrades", " OvenUpgrade", "Upgrade2", "Oven" },
	[3] = { "1ndFloor", "Kitchen", "Upgrades", " OvenUpgrade", "Upgrade1", "Oven" },
}

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "OvenView" })

--[[ Tables ]]--
local OvenView = {}
OvenView.__index = OvenView

export type OvenView = typeof(setmetatable(
	{} :: {
		Building: any,
		Janitor: any,
		LeftDoor: BasePart,
		RightDoor: BasePart,
		ClockHand: BasePart,
		LeftOpen: CFrame,
		RightOpen: CFrame,
		LeftClosed: CFrame,
		RightClosed: CFrame,
		ClockStart: CFrame,
		ClockAxis: Vector3,
		Dial: SurfaceGui,
		DoorClosed: boolean,
		FuelModel: Model?,
		FuelLogs: { Model },
		FuelRoot: Instance,
		FuelCount: number,
		FireEffects: { ParticleEmitter },
		FireEnabled: boolean?,
	},
	OvenView
))

--[[ Private Functions ]]--
local function resolvePart(model: Instance, name: string): BasePart?
	local part = model:FindFirstChild(name)

	return if part and part:IsA("BasePart") then part else nil
end

-- Rotates an authored pivot around a world-space axis while keeping the hinge point fixed.
local function rotatePivot(pivot: CFrame, axis: Vector3, angle: number): CFrame
	return CFrame.new(pivot.Position) * CFrame.fromAxisAngle(axis, angle) * pivot.Rotation
end

local function closedDoorPivot(openPivot: CFrame, part: BasePart, centre: Vector3): CFrame
	-- Imported leaves are thin on local X, tall on Y, and span the opening on Z.
	-- The hinge is offset through their thickness: aiming the bounding-box centre at the
	-- seam adds about 6.7 degrees and folds both leaves inward. Align only their width.
	local width = part.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -part.PivotOffset.Position.Z))
	local target = centre - openPivot.Position
	local currentDirection = Vector3.new(width.X, 0, width.Z).Unit
	local targetDirection = Vector3.new(target.X, 0, target.Z).Unit
	local angle =
		math.atan2(currentDirection:Cross(targetDirection):Dot(Vector3.yAxis), currentDirection:Dot(targetDirection))

	return rotatePivot(openPivot, Vector3.yAxis, angle)
end

local function phaseProgress(state: any, now: number): number
	if (state.HeatPausedAt or 0) > 0 then
		now = math.min(now, state.HeatPausedAt)
	end
	local startedAt = state.PhaseStartedAt or 0
	local endsAt = (if state.State == "Cooking" then state.ReadyAt else state.BurnAt) or 0
	local duration = endsAt - startedAt
	if startedAt <= 0 or duration <= 0 then
		return 0
	end

	return math.clamp((now - startedAt) / duration, 0, 1)
end

local function doorsAreClosed(state: string?): boolean
	-- Open as soon as baking finishes so the result is visible while it waits for collection.
	return state == "Loaded" or state == "Cooking"
end

--[[ Handling ]]--
function OvenView.new(root: Instance, building: any): OvenView?
	local path = MODEL_PATHS[building.Index]
	local model = path and BuildingsConfig.ResolvePath(root, path)
	if not model then
		return nil
	end

	local leftDoor = resolvePart(model, LEFT_DOOR_NAME)
	local rightDoor = resolvePart(model, RIGHT_DOOR_NAME)
	local clockHand = resolvePart(model, CLOCK_HAND_NAME)
	local body = resolvePart(model, BODY_NAME)
	if not leftDoor or not rightDoor or not clockHand or not body then
		return nil
	end

	local self = setmetatable({}, OvenView) :: OvenView
	self.Building = building
	self.Janitor = Janitor.new()
	self.FuelRoot = root
	self.FuelCount = -1
	self.FuelLogs = {}
	self.FireEffects = {}
	self:BindFire(body)
	self:BindFuel()
	self.LeftDoor = leftDoor
	self.RightDoor = rightDoor
	self.ClockHand = clockHand
	self.LeftOpen = leftDoor:GetPivot()
	self.RightOpen = rightDoor:GetPivot()
	self.ClockStart = clockHand:GetPivot()
	-- The imported mesh's thin local X axis is the clock-face normal; the oven body's LookVector
	-- follows its Blender axes and does not point out of the visible front.
	self.ClockAxis = clockHand.CFrame.RightVector
	local dialPart, dial = OvenDial.new(clockHand, body)
	self.Dial = dial
	self.Janitor:Add(dialPart, "Destroy")

	local hingeCentre = (self.LeftOpen.Position + self.RightOpen.Position) / 2
	self.LeftClosed = closedDoorPivot(self.LeftOpen, leftDoor, hingeCentre)
	self.RightClosed = closedDoorPivot(self.RightOpen, rightDoor, hingeCentre)
	self.DoorClosed = doorsAreClosed(building:GetState())
	self:BindDoor(leftDoor, self.LeftOpen, self.LeftClosed)
	self:BindDoor(rightDoor, self.RightOpen, self.RightClosed)

	self.Janitor:Add(function()
		if leftDoor.Parent then
			leftDoor:PivotTo(self.LeftOpen)
		end
		if rightDoor.Parent then
			rightDoor:PivotTo(self.RightOpen)
		end
		if clockHand.Parent then
			clockHand:PivotTo(self.ClockStart)
		end
	end, true)

	self:ApplyClock(workspace:GetServerTimeNow())

	return self
end

function OvenView.BindFire(self: OvenView, body: BasePart): ()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("VFX")
	local source = effects and effects:FindFirstChild(OvenFuel.EffectAsset)
	local offset = source and source:GetAttribute("BodyOffset")
	if not source or not source:IsA("BasePart") or typeof(offset) ~= "CFrame" then
		Logger:Warn(`Missing authored fire effect for {self.Building.Id}`)
		return
	end
	local fire = source:Clone()
	fire.Name = `Fire_{self.Building.Id}`
	fire.Anchored = true
	fire.CanCollide = false
	fire.CanTouch = false
	fire.CanQuery = false
	fire.Transparency = 1
	fire.CFrame = body.CFrame * offset
	for _, effect in fire:GetDescendants() do
		if not effect:IsA("ParticleEmitter") then
			continue
		end
		effect.Enabled = false
		self.FireEffects[#self.FireEffects + 1] = effect
	end
	fire.Parent = self.FuelRoot
	self.Janitor:Add(fire, "Destroy")
end

function OvenView.BindFuel(self: OvenView): ()
	local anchors = BaseHandler.Template:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(self.Building.Id)
	local surface = anchor and anchor:FindFirstChild(CarryConfig.OvenSurfaceAttachment)
	local transform = BaseHandler:GetTransform(self.Building.Player)
	if not surface or not surface:IsA("Attachment") or not transform then
		Logger:Warn(`Missing fuel attachment for {self.Building.Id}`)
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local ingredients = models and models:FindFirstChild("Ingredients")
	local source = ingredients and ingredients:FindFirstChild(CarryConfig.OvenStackAsset)
	if not source or not source:IsA("Model") then
		Logger:Warn("Missing authored oven fuel stack")
		return
	end
	local model = source:Clone()
	model.Name = `Fuel_{self.Building.Id}`
	model:SetAttribute("OwnerUserId", self.Building.Player.UserId)
	model:PivotTo(transform * surface.WorldCFrame)
	self.FuelModel = model
	self.Janitor:Add(model, "Destroy")
	for _, log in model:GetChildren() do
		if not log:IsA("Model") then
			continue
		end
		self.FuelLogs[#self.FuelLogs + 1] = log
		-- Hidden logs are detached, so own them separately for complete teardown.
		self.Janitor:Add(log, "Destroy")
	end
	table.sort(self.FuelLogs, function(left: Model, right: Model): boolean
		return left.Name < right.Name
	end)
	self:ApplyFuel()
end

function OvenView.ApplyFuel(self: OvenView): ()
	local state = self.Building.State
	local burning = state ~= nil and (state.Fuel or 0) > 0
	if self.FireEnabled ~= burning then
		self.FireEnabled = burning
		for _, effect in self.FireEffects do
			effect.Enabled = burning
		end
	end
	local model = self.FuelModel
	if not model then
		return
	end
	-- The authored firewood bed represents one timed charge, not a queue of recipe tokens.
	local count = if burning then #self.FuelLogs else 0
	if count == self.FuelCount then
		return
	end
	self.FuelCount = count
	for index, log in self.FuelLogs do
		log.Parent = if index <= count then model else nil
	end
	model.Parent = if count > 0 then self.FuelRoot else nil
end

function OvenView.BindDoor(self: OvenView, part: BasePart, open: CFrame, closed: CFrame): ()
	local canCollide = part.CanCollide
	-- A cosmetic leaf must not leave a server-side collision at its authored open position.
	part.CanCollide = false
	part:SetAttribute(Motion.OpenAttribute, open)
	part:SetAttribute(Motion.ClosedAttribute, closed)
	part:SetAttribute(Motion.TargetAttribute, self.DoorClosed)
	CollectionService:AddTag(part, Motion.Tag)
	self.Janitor:Add(function()
		CollectionService:RemoveTag(part, Motion.Tag)
		part:SetAttribute(Motion.OpenAttribute, nil)
		part:SetAttribute(Motion.ClosedAttribute, nil)
		part:SetAttribute(Motion.TargetAttribute, nil)
		part.CanCollide = canCollide
	end, true)
end

function OvenView.ApplyClock(self: OvenView, now: number): ()
	local state = self.Building.State
	local fraction = 0
	if state.State == "Cooking" or state.State == "Ready" then
		fraction = phaseProgress(state, now)
	elseif state.State == "Burnt" then
		fraction = 1
	end
	self.Dial.Enabled = state.State == "Ready" or state.State == "Burnt"

	-- Positive around the imported face normal is clockwise from the kitchen side.
	self.ClockHand:PivotTo(rotatePivot(self.ClockStart, self.ClockAxis, FULL_TURN * fraction))
end

function OvenView.Update(self: OvenView, _deltaTime: number, now: number): ()
	self:ApplyFuel()
	local target = doorsAreClosed(self.Building:GetState())
	if self.DoorClosed ~= target then
		self.DoorClosed = target
		self.LeftDoor:SetAttribute(Motion.TargetAttribute, target)
		self.RightDoor:SetAttribute(Motion.TargetAttribute, target)
	end

	self:ApplyClock(now)
end

function OvenView.Destroy(self: OvenView): ()
	self.Janitor:Destroy()
end

return OvenView
