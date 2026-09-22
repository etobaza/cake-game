--!strict
-- Food and ingredients fly onto the support-hand tray; firewood rests between both palms.
-- Every visible player's hold layer is Janitor-owned; no tray occupies an inventory slot.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Config = require(_Shared.Configs.FoodPresentation)
local CarryConfig = require(_Shared.Configs.CarryPresentation)
local CarryModel = require(_Shared.CarryModel)
local AnimationConfig = require(_Shared.Configs.CharacterAnimations)
local Appearance = require(_Shared.CarriedAppearance)
local FoodModel = require(_Shared.FoodModel)
local JointPose = require(_Shared.JointPose)
local HeldPose = require(_Shared.HeldPose)
local AnimalBrushView = require(_Shared.AnimalBrushView)
local PickupMotion = require(_Shared.PickupMotion)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Constants ]]--
local BIND_NAME = "CakeFoodTrays"

--[[ Types ]]--
type Carry = {
	Janitor: any,
	Visuals: any,
	Tray: FoodModel.FoodModel?,
	Food: FoodModel.FoodModel?,
	Character: Model?,
	Key: string?,
	Pose: HeldPose.HeldPose?,
	Brush: AnimalBrushView.AnimalBrushView?,
	Hand: string?,
	BetweenHands: boolean?,
	Flight: PickupMotion.Flight?,
}

--[[ Tables ]]--
local TrayHandler = {}

--[[ Private Functions ]]--
local function palmPosition(character: Model, side: string): Vector3?
	local hand = character:FindFirstChild(`{side}Hand`) or character:FindFirstChild(`{side} Arm`)
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local grip = hand:FindFirstChild(`{side}GripAttachment`)
	return if grip and grip:IsA("Attachment")
		then grip.WorldPosition
		else (hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)).Position
end

--[[ Handling ]]--
function TrayHandler.OnInit(self: TrayHandler): ()
	self.Carries = {}
	self.Janitor = Janitor.new()
	self.Root = Instance.new("Folder")
	self.Root.Name = "FoodTrays"
	self.Root.Parent = workspace
	self.Janitor:Add(self.Root, "Destroy")
end

function TrayHandler.Refresh(self: TrayHandler, player: Player): ()
	local carry = self.Carries[player]
	if not carry then
		return
	end
	local value = player:GetAttribute(Config.HandAttribute)
	local character = player.Character
	if carry.Key == value and carry.Character == character then
		return
	end
	local animatePickup = carry.Key ~= nil and carry.Key ~= value and carry.Character == character
	if carry.Character ~= character then
		carry.Janitor:Remove("Pose")
		carry.Janitor:Remove("Brush")
		carry.Brush = nil
		carry.Pose = nil
		if character then
			carry.Pose = HeldPose.new(character, self.PoseClips)
			carry.Janitor:Add(carry.Pose, "Destroy", "Pose")
			carry.Brush = AnimalBrushView.new(character, self.Root)
			carry.Janitor:Add(carry.Brush, "Destroy", "Brush")
		end
	end
	carry.Visuals:Cleanup()
	carry.Tray, carry.Food = nil, nil
	carry.Key = if typeof(value) == "string" then value else nil
	carry.Character = character
	local item = Appearance.Decode(value)
	carry.Flight = if animatePickup then PickupMotion.Begin(item, workspace:GetServerTimeNow()) else nil
	local entries = item and CarryConfig.Items[item.Kind]
	local entry = entries and item and item.Id and entries[item.Id]
	carry.BetweenHands = entry ~= nil and entry.BetweenHands == true
	if carry.Pose then
		carry.Pose:SetItem(item)
	end
	local holdName = Appearance.GetHold(item)
	local definition = holdName and AnimationConfig.Clips[holdName]
	carry.Hand = definition and definition.Hand
	if not character or not item or not Appearance.HasCarriedModel(item) then
		return
	end
	if not Appearance.HasTray(item) then
		local held = CarryModel.new(item, self.Root)
		carry.Food = held
		if held then
			held.Model.Parent = nil
			held.Model:SetAttribute("OwnerUserId", player.UserId)
			carry.Visuals:Add(held, "Destroy")
		end
		return
	end
	local tray = FoodModel.new("Tray", self.Root, Config.TraySize)
	if not tray then
		warn("[TrayHandler] Cake.Tray is missing")
		return
	end
	-- Reveal only after the hand and root have streamed in and the pose has been resolved.
	tray.Model.Parent = nil
	carry.Tray = tray
	carry.Visuals:Add(tray, "Destroy")
	tray.Model:SetAttribute("OwnerUserId", player.UserId)
	if not item or not item.Id then
		return
	end
	local food = if item.Kind == "Ingredient"
		then CarryModel.new(item, tray.Model)
		else FoodModel.ForItem(item.Id, item.Kind, tray.Model, Config.FoodSize)
	carry.Food = food
	if food then
		carry.Visuals:Add(food, "Destroy")
	end
end

function TrayHandler.Attach(self: TrayHandler, player: Player): ()
	if self.Carries[player] then
		return
	end
	local carry: Carry = { Janitor = Janitor.new(), Visuals = Janitor.new() }
	carry.Janitor:Add(carry.Visuals, "Destroy")
	self.Carries[player] = carry
	carry.Janitor:Add(
		player:GetAttributeChangedSignal(Config.HandAttribute):Connect(function()
			self:Refresh(player)
		end),
		"Disconnect"
	)
	carry.Janitor:Add(
		player.CharacterAdded:Connect(function()
			self:Refresh(player)
		end),
		"Disconnect"
	)
	carry.Janitor:Add(
		player.CharacterRemoving:Connect(function()
			carry.Janitor:Remove("Pose")
			carry.Janitor:Remove("Brush")
			carry.Brush = nil
			carry.Pose = nil
			carry.Visuals:Cleanup()
			carry.Tray, carry.Food, carry.Character, carry.Key = nil, nil, nil, nil
			carry.Flight = nil
		end),
		"Disconnect"
	)
	self:Refresh(player)
end

function TrayHandler.Detach(self: TrayHandler, player: Player): ()
	local carry = self.Carries[player]
	if carry then
		carry.Janitor:Destroy()
	end
	self.Carries[player] = nil
end

function TrayHandler.Align(self: TrayHandler): ()
	local now = workspace:GetServerTimeNow()
	for _, carry in self.Carries do
		if carry.Brush then
			carry.Brush:Align()
		end
		local character, tray = carry.Character, carry.Tray
		local visual = tray or carry.Food
		if not character or not visual then
			continue
		end
		local side = carry.Hand
		if not side then
			continue
		end
		local palm = palmPosition(character, side)
		if carry.BetweenHands and palm then
			local other = palmPosition(character, if side == "Left" then "Right" else "Left")
			palm = if other then (palm + other) / 2 else nil
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not palm or not root or not root:IsA("BasePart") then
			visual.Model.Parent = nil
			continue
		end
		local direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if direction.Magnitude < 0.01 then
			continue
		end
		local offset = if tray then Config.HandOffset else CarryConfig.HandOffset
		local pose = CFrame.lookAt(palm, palm + direction) * CFrame.new(offset)
		local food = carry.Food
		if not tray and food then
			pose = PickupMotion.Sample(carry.Flight, pose, Vector3.new(0, food.Size.Y / 2, 0), now)
		end
		visual:SetCFrame(pose)
		visual.Model.Parent = self.Root
		if tray and food then
			local target = pose * CFrame.new(0, tray.Size.Y + Config.TrayClearance, 0)
			food:SetCFrame(PickupMotion.Sample(carry.Flight, target, Vector3.new(0, food.Size.Y / 2, 0), now))
		end
	end
end

function TrayHandler.OnStart(self: TrayHandler): ()
	self.PoseClips = HeldPose.ReadClips()
	self.Janitor:Add(
		Players.PlayerAdded:Connect(function(player: Player)
			self:Attach(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player)
			self:Detach(player)
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		self:Attach(player)
	end
	-- One pair of visual callbacks for all players: restore before Animator, overlay before physics.
	self.Janitor:Add(
		RunService.PreAnimation:Connect(function(): ()
			for _, carry in self.Carries do
				if carry.Brush then
					carry.Brush:Step(workspace:GetServerTimeNow())
				end
				if carry.Pose then
					carry.Pose:Restore()
				end
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		RunService.PreSimulation:Connect(function(deltaTime: number): ()
			self:PoseArms(deltaTime)
		end),
		"Disconnect"
	)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value + 1, function()
		self:Align()
	end)
	self.Janitor:Add(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end, true)
end

function TrayHandler.PoseArms(self: TrayHandler, deltaTime: number): ()
	local time = workspace:GetServerTimeNow()
	for _, carry in self.Carries do
		local pose = carry.Pose
		if not pose then
			continue
		end
		pose:Step(deltaTime, time)
	end
end

function TrayHandler.Destroy(self: TrayHandler): ()
	for player in self.Carries do
		self:Detach(player)
	end
	self.Janitor:Destroy()
end

export type TrayHandler = typeof(TrayHandler) & {
	Carries: { [Player]: Carry },
	Root: Folder,
	Janitor: any,
	PoseClips: { [string]: JointPose.Clip },
}
return TrayHandler :: TrayHandler
