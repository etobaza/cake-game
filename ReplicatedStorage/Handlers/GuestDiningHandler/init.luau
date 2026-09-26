--!strict
-- Tags and server timestamps support late joining and streamed guest recreation.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Configs.GuestDining)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local JointPose = require(ReplicatedStorage.Shared.JointPose)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)
local Visual = require(script.Visual)

local BIND_NAME = "CakeGuestMeals"
local GuestDiningHandler = { dependencies = { "UIHandler" } }

function GuestDiningHandler.OnInit(self: GuestDiningHandler): ()
	self.Janitor = Janitor.new()
	self.Guests = {}
	self.Views = {}
end

function GuestDiningHandler.Remove(self: GuestDiningHandler, instance: Instance): ()
	if not instance:IsA("Model") then
		return
	end

	local view = self.Views[instance]
	if view then
		view:Destroy()
	end

	self.Views[instance] = nil
	self.Guests[instance] = nil
end

function GuestDiningHandler.Update(self: GuestDiningHandler): ()
	local now = workspace:GetServerTimeNow()

	for model in self.Guests do
		if not model:IsDescendantOf(workspace) then
			self:Remove(model)
			continue
		end

		-- Retry incomplete streamed bodies without yielding or creating duplicate views.
		local view: Visual.Visual? = self.Views[model] or Visual.new(model, self.Template, self.HandClip)
		if not view then
			continue
		end

		self.Views[model] = view
		view:Step(now)
	end
end

function GuestDiningHandler.OnStart(self: GuestDiningHandler): ()
	local animations = ReplicatedStorage.Assets:WaitForChild("Animations", 10)
	local sequence = animations and animations:WaitForChild(Config.HandSequence, 10)

	if sequence and sequence:IsA("KeyframeSequence") then
		self.HandClip = JointPose.Read(sequence, Config.HandJoints)
	else
		print(`[GuestDiningHandler] Missing authored {Config.HandSequence}`)
	end

	local order = UIHandler:GetHud("Order")
	local bar = order:FindFirstChild("Bar", true) :: CanvasGroup
	self.Template = bar:Clone()
	self.Janitor:Add(self.Template, "Destroy")

	local function add(instance: Instance): ()
		if instance:IsA("Model") then
			self.Guests[instance] = true
		end
	end

	self.Janitor:Add(CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(add), "Disconnect")
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(instance: Instance): ()
			self:Remove(instance)
		end),
		"Disconnect"
	)

	for _, instance in CollectionService:GetTagged(Config.Tag) do
		add(instance)
	end

	self.Janitor:Add(
		RunService.PreAnimation:Connect(function(): ()
			for _, view in self.Views do
				view:Restore()
			end

			self:Update()
		end),
		"Disconnect"
	)

	self.Janitor:Add(
		RunService.PreSimulation:Connect(function(deltaTime: number): ()
			local now = workspace:GetServerTimeNow()

			for _, view in self.Views do
				view:Animate(deltaTime, now)
			end
		end),
		"Disconnect"
	)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value + 1, function(): ()
		for _, view in self.Views do
			view:Align()
		end
	end)

	self.Janitor:Add(function(): ()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end, true)
end

function GuestDiningHandler.Destroy(self: GuestDiningHandler): ()
	for model in self.Guests do
		self:Remove(model)
	end

	self.Janitor:Destroy()
end

export type GuestDiningHandler = typeof(GuestDiningHandler) & {
	Janitor: any,
	Template: CanvasGroup,
	HandClip: JointPose.Clip?,
	Guests: { [Model]: boolean },
	Views: { [Model]: Visual.Visual },
}

return GuestDiningHandler :: GuestDiningHandler
