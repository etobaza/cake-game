--!strict
-- A player's disposable tool mesh and cached character bindings, shared by all observers.
--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Appearance = require(ReplicatedStorage.Shared.CarriedAppearance)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Config = require(ReplicatedStorage.Shared.Configs.ToolPresentation)
local FoodConfig = require(ReplicatedStorage.Shared.Configs.FoodPresentation)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local PickupMotion = require(ReplicatedStorage.Shared.PickupMotion)

--[[ Tables ]]--
local Tool = {}
Tool.__index = Tool

export type Tool = typeof(setmetatable(
	{} :: {
		Player: Player,
		Root: Folder,
		Janitor: any,
		Character: Model?,
		Mesh: BasePart?,
		Hand: BasePart?,
		Body: BasePart?,
		Humanoid: Humanoid?,
		Grip: Attachment?,
		ToolGrip: Attachment?,
		ToolId: string?,
		Extra: CFrame,
		Along: number,
		Key: string?,
		Flight: PickupMotion.Flight?,
	},
	Tool
))

--[[ Handling ]]--
function Tool.new(player: Player, root: Folder): Tool
	local self: Tool = setmetatable({
		Player = player,
		Root = root,
		Janitor = Janitor.new(),
		Extra = CFrame.identity,
		Along = Config.GripAlong,
	}, Tool)
	self.Janitor:Add(
		player.CharacterAdded:Connect(function(model: Model): ()
			self:Bind(model)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		player.CharacterRemoving:Connect(function(): ()
			self:Bind(nil)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		player:GetAttributeChangedSignal(FoodConfig.HandAttribute):Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self:Bind(player.Character)
	return self
end

function Tool.Bind(self: Tool, character: Model?): ()
	self.Janitor:Remove("Character")
	self.Janitor:Remove("Mesh")
	self.Character, self.Mesh, self.ToolId = character, nil, nil
	self.Hand, self.Body, self.Humanoid, self.Grip, self.ToolGrip = nil, nil, nil, nil, nil
	self.Key, self.Flight = nil, nil
	if not character then
		return
	end
	self.Janitor:Add(
		character.DescendantAdded:Connect(function(): ()
			self:Resolve()
		end),
		"Disconnect",
		"Character"
	)
	self:Resolve()
	self:Refresh()
end

function Tool.Resolve(self: Tool): ()
	local model = self.Character
	if not model then
		return
	end
	self.Hand = (model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")) :: BasePart?
	self.Body = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Humanoid = model:FindFirstChildOfClass("Humanoid")
	self.Grip = self.Hand and self.Hand:FindFirstChild("RightGripAttachment") :: Attachment?
end

function Tool.Refresh(self: Tool): ()
	local value = self.Player:GetAttribute(FoodConfig.HandAttribute)
	local item = Appearance.Decode(value)
	local id = if item and item.Kind == "Tool" then item.Id else nil
	local changed = self.Key ~= value
	local animatePickup = self.Key ~= nil and changed
	self.Key = if typeof(value) == "string" then value else nil
	if self.ToolId == id and not changed and (id == nil or self.Mesh ~= nil) then
		return
	end
	self.Flight = if animatePickup then PickupMotion.Begin(item, workspace:GetServerTimeNow()) else nil
	self.Janitor:Remove("Mesh")
	self.Mesh, self.ToolId, self.ToolGrip = nil, id, nil
	if not self.Character or not id then
		return
	end
	local kind = Buildings.KindForTool(id)
	local asset = kind and (kind.HeldAsset or (kind.Furniture and kind.Furniture.Asset))
	local source = asset and Buildings.FindAsset(asset)
	local original = source and source:FindFirstChildWhichIsA("BasePart", true)
	if not kind or not original then
		print(`[ToolViewHandler] Missing authored tool {id}`)
		return
	end
	local mesh = original:Clone()
	mesh.Name = "HeldTool"
	mesh.Size *= kind.HeldScale or 1
	mesh.Anchored, mesh.CanCollide, mesh.CanQuery, mesh.CanTouch = true, false, false, false
	mesh.Massless = true
	mesh:SetAttribute("ToolId", id)
	mesh:SetAttribute("OwnerUserId", self.Player.UserId)
	local toolGrip = mesh:FindFirstChild(Config.HandOrigin)
	self.ToolGrip = if toolGrip and toolGrip:IsA("Attachment") then toolGrip else nil
	self.Extra, self.Along = kind.Grip or CFrame.identity, kind.GripAlong or Config.GripAlong
	self.Mesh = mesh
	self.Janitor:Add(mesh, "Destroy", "Mesh")
end

function Tool.Step(self: Tool): ()
	local mesh, hand, body, humanoid = self.Mesh, self.Hand, self.Body, self.Humanoid
	if not mesh then
		return
	end
	if
		not hand
		or not body
		or not humanoid
		or not hand.Parent
		or not body.Parent
		or humanoid.Health <= 0
		or not self.Character
		or not self.Character:IsDescendantOf(workspace)
	then
		mesh.Parent = nil
		return
	end
	-- The animation rig's motor relation is hand * C0 * C1^-1, stored inversely in HandOrigin.
	-- Following the complete wrist frame preserves authored position AND rotation during holds/work.
	if self.ToolGrip then
		local target = hand.CFrame * self.ToolGrip.CFrame:Inverse()
		mesh.CFrame = PickupMotion.Sample(self.Flight, target, Vector3.zero, workspace:GetServerTimeNow())
		mesh.Parent = self.Root
		return
	end
	local palm = if self.Grip then self.Grip.WorldPosition else hand.Position
	local shaft = (
		-Vector3.yAxis
		- body.CFrame.LookVector * Config.ShaftBack
		+ body.CFrame.RightVector * Config.ShaftRight
	).Unit
	local up = -shaft
	local right = body.CFrame.LookVector:Cross(up)
	if right.Magnitude < 0.05 then
		right = body.CFrame.RightVector:Cross(up)
	end
	local look = right.Unit:Cross(up)
	local target = CFrame.fromMatrix(palm - up * (mesh.Size.Y * self.Along), look, up) * self.Extra
	mesh.CFrame = PickupMotion.Sample(self.Flight, target, Vector3.zero, workspace:GetServerTimeNow())
	mesh.Parent = self.Root
end

function Tool.Destroy(self: Tool): ()
	self.Janitor:Destroy()
	self.Mesh = nil
	self.ToolGrip = nil
end

return Tool
