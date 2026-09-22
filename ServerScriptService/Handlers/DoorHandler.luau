--!strict
-- The authored entrance sign follows the shift; door leaves keep their authored pose.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local BaseHandler = require(script.Parent.BaseHandler)
local DayCycleHandler = require(script.Parent.DayCycleHandler)
local DataHandler = require(script.Parent.DataHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "DoorHandler" })

local DoorHandler = { dependencies = { "BaseHandler", "DayCycleHandler", "DataHandler" } }
local FLIP_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
type SignBinding = { Model: Model, Closed: CFrame, Opened: CFrame, Value: CFrameValue, Janitor: any }

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
	local sign = exterior and exterior:FindFirstChild("SignOpen/Closed", true)
	if not exterior or not sign or not sign:IsA("Model") then
		Logger:Warn(`No entrance sign in {bakery.Name}`)
		return
	end
	local janitor = Janitor.new()
	-- Fixed closed leaves must not obstruct the established entrance route.
	for _, door in exterior:GetChildren() do
		if door.Name ~= "Door" then
			continue
		end
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
	end
	local closed = sign:GetPivot()
	local value = Instance.new("CFrameValue")
	value.Name = "SignPose"
	value.Value = closed
	value.Parent = sign
	janitor:Add(
		value.Changed:Connect(function(frame: CFrame)
			sign:PivotTo(frame)
		end),
		"Disconnect"
	)
	janitor:Add(value, "Destroy")
	local opened = CFrame.new(closed.Position) * CFrame.Angles(0, math.pi, 0) * closed.Rotation
	self.Bases[player] = { Model = sign, Closed = closed, Opened = opened, Value = value, Janitor = janitor }
	local data = DataHandler:GetData(player)
	self:SetOpen(player, data ~= nil and data.Session.Day.Phase == "Shift")
end

function DoorHandler.SetOpen(self: DoorHandler, player: Player, isOpen: boolean): ()
	local binding = self.Bases[player]
	if not binding then
		return
	end
	binding.Model:SetAttribute("CafeOpen", isOpen)
	local tween =
		TweenService:Create(binding.Value, FLIP_INFO, { Value = if isOpen then binding.Opened else binding.Closed })
	binding.Janitor:Add(tween, "Cancel", "Flip")
	tween:Play()
end

function DoorHandler.Unbind(self: DoorHandler, player: Player): ()
	local binding = self.Bases[player]
	if not binding then
		return
	end
	self.Bases[player] = nil
	binding.Janitor:Destroy()
	if binding.Model.Parent then
		binding.Model:PivotTo(binding.Closed)
		binding.Model:SetAttribute("CafeOpen", nil)
	end
end

export type DoorHandler = typeof(DoorHandler) & { Bases: { [Player]: SignBinding } }
return DoorHandler :: DoorHandler
