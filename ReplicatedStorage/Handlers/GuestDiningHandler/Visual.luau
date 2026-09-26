--!strict
-- The server owns the meal deadline; this view owns its local food, arm pose and progress card.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.GuestDining)
local FoodModel = require(ReplicatedStorage.Shared.FoodModel)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Clearance = require(script.Parent.Clearance)
local JointPose = require(ReplicatedStorage.Shared.JointPose)
local PlateMotion = require(script.Parent.PlateMotion)

local Visual = {}
Visual.__index = Visual

export type Visual = typeof(setmetatable(
	{} :: {
		Model: Model,
		Head: BasePart,
		Janitor: any,
		Panel: CanvasGroup,
		Clip: Frame,
		Fill: Frame,
		Label: TextLabel,
		Food: FoodModel.FoodModel?,
		Hand: BasePart?,
		Pose: JointPose.JointPose?,
		HandClip: JointPose.Clip?,
		Plate: PlateMotion.PlateMotion?,
		HeadParts: { BasePart },
		NextHeadScanAt: number,
		PoseStartedAt: number,
	},
	Visual
))

local function smooth(value: number): number
	local alpha = math.clamp(value, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

function Visual.new(model: Model, template: CanvasGroup, handClip: JointPose.Clip?): Visual?
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EatingProgress"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(Config.BarSize.X, Config.BarSize.Y)
	billboard.StudsOffsetWorldSpace = Config.BarOffset
	billboard.MaxDistance = Config.MaxDistance
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Parent = model
	local panel = Instance.new("CanvasGroup")
	panel.Name = "Meal"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.PanelFill
	panel.BorderSizePixel = 0
	panel.GroupTransparency = 1
	panel.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Config.CornerRadius)
	corner.Parent = panel
	local outline = Instance.new("UIStroke")
	outline.Color = Theme.Colors.PanelEdge
	outline.Thickness = Config.StrokeThickness
	outline.Parent = panel
	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(Config.BarPadding, 0)
	label.Size = UDim2.new(1, -Config.BarPadding * 2, 1, -Config.BarHeight - Config.BarPadding)
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = Config.TextSize
	label.TextColor3 = Theme.Colors.Cocoa
	label.Text = "Enjoying..."
	label.Parent = panel
	-- Preserve the order HUD's exact border, mask and striped artwork.
	local bar = template:Clone()
	bar.Name = "Progress"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, Config.BarPadding, 1, -Config.BarPadding)
	bar.Size = UDim2.new(1, -Config.BarPadding * 2, 0, Config.BarHeight)
	bar.Visible = true
	bar.GroupTransparency = 0
	bar.Parent = panel
	local clip = bar:FindFirstChild("Clip") :: Frame
	local fill = clip:FindFirstChild("Fill") :: Frame
	local gradient = fill:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = Theme.ProgressGradient
		gradient.Rotation = 90
	end
	clip.Size = UDim2.fromScale(0, 1)
	local self: Visual = setmetatable({
		Model = model,
		HandClip = handClip,
		Head = head,
		Janitor = Janitor.new(),
		Panel = panel,
		Clip = clip,
		Fill = fill,
		Label = label,
		HeadParts = Clearance.Collect(model, head),
		NextHeadScanAt = 0,
		PoseStartedAt = 0,
	}, Visual)
	self.Janitor:Add(billboard, "Destroy")
	return self
end

function Visual.BindFood(self: Visual, now: number): ()
	local recipeId = self.Model:GetAttribute(Config.HeldAttribute)
	if typeof(recipeId) ~= "string" or not Config.Handheld[recipeId] then
		return
	end

	local hand = self.Model:FindFirstChild("RightHand")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	local food = FoodModel.ForItem(recipeId, "Dish", self.Model, Config.FoodSize)
	if not food then
		return
	end

	food.Model.Name = "HeldMeal"
	food.Model.Parent = nil
	self.Janitor:Add(food, "Destroy")

	if self.HandClip then
		self.Pose = JointPose.new(self.Model, self.HandClip, Config.HandJoints, Config.PoseFadeSeconds)
		self.Janitor:Add(self.Pose, "Destroy")
	end

	self.Food, self.Hand = food, hand
	self.PoseStartedAt = now
end

function Visual.Step(self: Visual, now: number): ()
	local started = self.Model:GetAttribute(Config.StartedAttribute)
	local ends = self.Model:GetAttribute(Config.EndsAttribute)
	if typeof(started) ~= "number" or typeof(ends) ~= "number" or ends <= started then
		return
	end
	local elapsed = math.max(0, now - started)
	local progress = math.clamp(elapsed / (ends - started), 0, 1)
	self.Panel.GroupTransparency = 1 - smooth(elapsed / Config.FadeSeconds)
	self.Clip.Size = UDim2.fromScale(progress, 1)
	self.Clip.Visible = progress > 0
	self.Fill.Size = UDim2.fromScale(if progress > 0 then 1 / progress else 1, 1)
	self.Label.Text = if progress >= 1 then "Delicious!" else `Enjoying... {math.floor(progress * 100)}%`

	if now >= self.NextHeadScanAt then
		self.HeadParts = Clearance.Collect(self.Model, self.Head)
		self.NextHeadScanAt = now + Config.HeadBoundsRefreshSeconds
	end

	if not self.Food then
		self:BindFood(now)
	end
	if not self.Food and not self.Plate and self.Model:GetAttribute(Config.HeldAttribute) == nil then
		self.Plate = PlateMotion.new(self.Model)

		if self.Plate then
			self.Janitor:Add(self.Plate, "Destroy")
		end
	end

	if self.Plate then
		self.Plate:Step(now, started, ends)
	end
end

function Visual.Restore(self: Visual): ()
	if self.Plate then
		self.Plate:Restore()
	end

	if self.Pose then
		self.Pose:Restore()
	end
end

function Visual.Animate(self: Visual, deltaTime: number, now: number): ()
	if self.Plate then
		self.Plate:Animate(deltaTime)
	end

	local ends = self.Model:GetAttribute(Config.EndsAttribute)
	local started = self.Model:GetAttribute(Config.StartedAttribute)

	if self.Pose and typeof(ends) == "number" and typeof(started) == "number" then
		self.Pose:Step(deltaTime, now < ends - Config.PoseFadeSeconds, math.max(0, now - started), nil, nil, nil)
	end
end

function Visual.Align(self: Visual): ()
	if self.Plate then
		self.Plate:Align()
	end

	local food, hand = self.Food, self.Hand
	if not food or not hand or not hand.Parent then
		return
	end

	-- Preserve the authored hand motion while keeping large food outside avatar accessories.
	local frame =
		Clearance.KeepOutside(self.Head, self.HeadParts, hand.CFrame * Config.Grip, food.Size, Config.FaceClearance)
	food:SetCFrame(frame)
	food.Model.Parent = self.Model
end

function Visual.Destroy(self: Visual): ()
	self.Janitor:Destroy()
end

return Visual
