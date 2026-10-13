--!strict
-- The shift owns entrance targets. Clients move the authored leaves and their nested sign.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BaseHandler = require(script.Parent.BaseHandler)
local DayCycleHandler = require(script.Parent.DayCycleHandler)
local DataHandler = require(script.Parent.DataHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "DoorHandler" })
local Motion = require(ReplicatedStorage.Shared.Configs.CookingMotion)
local WorldPose = require(ReplicatedStorage.Shared.WorldPose)

local DoorHandler = { dependencies = { "BaseHandler", "DayCycleHandler", "DataHandler" } }
type Leaf = { Model: Model, Sign: Model? }
type EntranceBinding = { Leaves: { Leaf }, Janitor: any }

-- Select the outward quarter turn around the artist's frame hinge, never its model centre.
local function openedPivot(model: Model, frame: BasePart, outward: Vector3): CFrame
	local hinge = frame:GetPivot().Position
	local closed = model:GetPivot()
	local best = closed
	local bestDistance = -math.huge
	for _, angle in { math.pi / 2, -math.pi / 2 } do
		local delta = CFrame.new(hinge) * CFrame.Angles(0, angle, 0) * CFrame.new(-hinge)
		local distance = (delta:PointToWorldSpace(frame.Position) - frame.Position):Dot(outward)
		if distance > bestDistance then
			best, bestDistance = delta * closed, distance
		end
	end
	return best
end

local function bindLeaf(door: Model, outward: Vector3, janitor: any): Leaf?
	local frame = door:FindFirstChild("Cube.083")
	if not frame or not frame:IsA("BasePart") then
		Logger:Warn(`Missing authored entrance hinge in {door:GetFullName()}`)
		return nil
	end
	local closed = door:GetPivot()
	local bounds, size = door:GetBoundingBox()
	local signChild = door:FindFirstChild("SignOpen/Closed")
	local sign = if signChild and signChild:IsA("Model") then signChild else nil
	local signClosed = sign and sign:GetPivot()
	for _, part in door:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local collision = part.CanCollide
		part.CanCollide = false
		janitor:Add(function(): ()
			if part.Parent then
				part.CanCollide = collision
			end
		end, true)
	end
	door:SetAttribute(WorldPose.PivotAttribute, closed)
	door:SetAttribute(WorldPose.FrameAttribute, bounds)
	door:SetAttribute(WorldPose.SizeAttribute, size)
	door:SetAttribute("EntranceClosedPivot", closed)
	door:SetAttribute("EntranceOpenPivot", openedPivot(door, frame, outward))
	door:SetAttribute(Motion.Entrance.HingePosition, frame:GetPivot().Position)
	if sign and signClosed then
		local opened = CFrame.new(signClosed.Position) * CFrame.Angles(0, math.pi, 0) * signClosed.Rotation
		sign:SetAttribute("SignClosedLocal", closed:ToObjectSpace(signClosed))
		sign:SetAttribute("SignOpenLocal", closed:ToObjectSpace(opened))
	end
	janitor:Add(function(): ()
		door:RemoveTag(Motion.EntranceTag)
		if door.Parent then
			door:PivotTo(closed)
		end
		if sign and signClosed and sign.Parent then
			sign:PivotTo(signClosed)
			for _, attribute in { "SignClosedLocal", "SignOpenLocal", "CafeOpen" } do
				sign:SetAttribute(attribute, nil)
			end
		end
		for _, attribute in
			{
				WorldPose.PivotAttribute,
				WorldPose.FrameAttribute,
				WorldPose.SizeAttribute,
				"EntranceClosedPivot",
				"EntranceOpenPivot",
				"EntranceHingePosition",
				"CafeOpen",
			}
		do
			door:SetAttribute(attribute, nil)
		end
	end, true)
	return { Model = door, Sign = sign }
end

function DoorHandler.OnInit(self: DoorHandler): ()
	self.Bases = {}
end

function DoorHandler.OnStart(self: DoorHandler): ()
	BaseHandler.BaseReady:Connect(function(player: Player, bakery: Folder)
		self:Bind(player, bakery)
	end)
	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:Unbind(player)
	end)
	DayCycleHandler.PhaseChanged:Connect(function(player: Player, phase: string)
		self:SetOpen(player, phase == "Shift")
	end)
	for _, player in Players:GetPlayers() do
		local bakery = BaseHandler:GetBase(player)
		if bakery then
			self:Bind(player, bakery)
		end
	end
end

function DoorHandler.Bind(self: DoorHandler, player: Player, bakery: Folder): ()
	if self.Bases[player] then
		return
	end
	local floor = bakery:FindFirstChild("1ndFloor")
	local exterior = floor and floor:FindFirstChild(" exterior")
	local anchor = BaseHandler:GetAnchor("door")
	local transform = BaseHandler:GetTransform(player)
	if not exterior or not anchor or not transform then
		Logger:Warn(`No entrance geometry in {bakery.Name}`)
		return
	end
	local janitor = Janitor.new()
	local leaves: { Leaf } = {}
	local outward = (transform * anchor).LookVector
	for _, door in exterior:GetChildren() do
		if door.Name ~= "Door" or not door:IsA("Model") then
			continue
		end
		local leaf = bindLeaf(door, outward, janitor)
		if leaf then
			table.insert(leaves, leaf)
		end
	end
	self.Bases[player] = { Leaves = leaves, Janitor = janitor }
	local data = DataHandler:GetData(player)
	self:SetOpen(player, data ~= nil and data.Session.Day.Phase == "Shift")
	for _, leaf in leaves do
		leaf.Model:AddTag(Motion.EntranceTag)
	end
end

function DoorHandler.SetOpen(self: DoorHandler, player: Player, isOpen: boolean): ()
	local binding = self.Bases[player]
	if not binding then
		return
	end
	for _, leaf in binding.Leaves do
		leaf.Model:SetAttribute("CafeOpen", isOpen)
		if leaf.Sign then
			leaf.Sign:SetAttribute("CafeOpen", isOpen)
		end
	end
end

function DoorHandler.Unbind(self: DoorHandler, player: Player): ()
	local binding = self.Bases[player]
	if not binding then
		return
	end
	self.Bases[player] = nil
	binding.Janitor:Destroy()
end

export type DoorHandler = typeof(DoorHandler) & { Bases: { [Player]: EntranceBinding } }
return DoorHandler :: DoorHandler
