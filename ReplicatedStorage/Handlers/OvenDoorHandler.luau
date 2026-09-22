--!strict
-- Smooth local hinge motion for every owned oven. The server supplies targets, never frame poses.

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Motion = require(ReplicatedStorage.Shared.Configs.OvenMotion)

--[[ Tables ]]--
local OvenDoorHandler = {}

--[[ Private Functions ]]--
local function bindDoor(part: BasePart): any
	local janitor = Janitor.new()
	local pose = Instance.new("CFrameValue")
	pose.Value = part:GetPivot()
	janitor:Add(pose, "Destroy")
	local openPivot: CFrame? = nil
	local target: CFrame? = nil
	local initialized = false

	janitor:Add(
		pose.Changed:Connect(function(value: CFrame)
			part:PivotTo(value)
		end),
		"Disconnect"
	)

	local function refresh(): ()
		local open = part:GetAttribute(Motion.OpenAttribute)
		local closed = part:GetAttribute(Motion.ClosedAttribute)
		local isClosed = part:GetAttribute(Motion.TargetAttribute)
		if typeof(open) ~= "CFrame" or typeof(closed) ~= "CFrame" or typeof(isClosed) ~= "boolean" then
			return
		end

		openPivot = open
		local goal = if isClosed then closed else open
		if target == goal then
			return
		end
		target = goal
		janitor:Remove("Travel")
		-- Catch up a streamed-in or already occupied oven without replaying its old transition.
		if not initialized then
			initialized = true
			pose.Value = goal
			part:PivotTo(goal)
			return
		end

		local tween = TweenService:Create(
			pose,
			TweenInfo.new(Motion.TravelSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Value = goal }
		)
		janitor:Add(function()
			tween:Cancel()
			tween:Destroy()
		end, true, "Travel")
		tween:Play()
	end

	for _, attribute in { Motion.OpenAttribute, Motion.ClosedAttribute, Motion.TargetAttribute } do
		janitor:Add(part:GetAttributeChangedSignal(attribute):Connect(refresh), "Disconnect")
	end
	refresh()

	return {
		Destroy = function(): ()
			-- Stop motion before disconnecting its value listener or destroying its value object.
			janitor:Remove("Travel")
			janitor:Destroy()
			if openPivot and part.Parent then
				part:PivotTo(openPivot)
			end
		end,
	}
end

--[[ Handling ]]--
function OvenDoorHandler.OnInit(self: OvenDoorHandler): ()
	self.Janitor = Janitor.new()
	self.Doors = {}
end

function OvenDoorHandler.OnStart(self: OvenDoorHandler): ()
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(Motion.Tag):Connect(function(instance: Instance)
			self:Track(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Motion.Tag):Connect(function(instance: Instance)
			self:Untrack(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Motion.Tag) do
		self:Track(instance)
	end
end

function OvenDoorHandler.Track(self: OvenDoorHandler, instance: Instance): ()
	if not instance:IsA("BasePart") or self.Doors[instance] then
		return
	end
	self.Doors[instance] = true
	self.Janitor:Add(bindDoor(instance), "Destroy", instance)
end

function OvenDoorHandler.Untrack(self: OvenDoorHandler, instance: Instance): ()
	self.Janitor:Remove(instance)
	self.Doors[instance] = nil
end

function OvenDoorHandler.Destroy(self: OvenDoorHandler): ()
	self.Janitor:Destroy()
	table.clear(self.Doors)
end

export type OvenDoorHandler = typeof(OvenDoorHandler) & {
	Janitor: any,
	Doors: { [Instance]: boolean },
}

return OvenDoorHandler :: OvenDoorHandler
