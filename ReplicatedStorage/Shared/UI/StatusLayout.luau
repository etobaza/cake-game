--!strict
-- Sizes the authored status toast without creating another notification surface.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]
--
local Animate = require(script.Parent.Animate)
local Config = require(ReplicatedStorage.Shared.Configs.Notifications)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local TextScale = require(script.Parent.TextScale)

--[[ Tables ]]
--
local StatusLayout = {}

--[[ Private Functions ]]
--
local function prepareArtwork(frame: GuiObject): ()
	local background = frame:FindFirstChild("Background")
	if background and background:IsA("ImageLabel") then
		background.AnchorPoint = Vector2.one / 2
		background.Position = UDim2.fromScale(0.5, 0.5)
		background.Size = UDim2.fromScale(1, 1)
		background.ScaleType = Enum.ScaleType.Stretch
	end

	-- The decorative caption and dashed lines consume space needed by a short toast.
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and (child.Name == "Lines" or child.Name == "Tag") then
			child.Visible = false
		end
	end
end

local function restingRectangle(group: GuiObject): (number, number)
	local top = group.AbsolutePosition.Y
	local height = group.AbsoluteSize.Y
	local home = group:GetAttribute("HomePosition")
	local parent = group.Parent
	if typeof(home) == "UDim2" and parent and parent:IsA("GuiObject") then
		-- The resting rectangle ignores the group's entrance and press springs.
		height = parent.AbsoluteSize.Y * group.Size.Y.Scale + group.Size.Y.Offset
		local anchorY = parent.AbsolutePosition.Y + parent.AbsoluteSize.Y * home.Y.Scale + home.Y.Offset
		top = anchorY - height * group.AnchorPoint.Y
	end
	return top, height
end

local function restingBottom(group: GuiObject, includeChildren: boolean): number
	local top, height = restingRectangle(group)
	local bottom = top + height
	if includeChildren then
		-- Currency's boost/Invite row can extend below the authored group. Use its
		-- direct children's layout properties, not rendered press/pop bounds.
		for _, child in group:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local childHeight = height * child.Size.Y.Scale + child.Size.Y.Offset
				local anchorY = top + height * child.Position.Y.Scale + child.Position.Y.Offset
				bottom = math.max(bottom, anchorY + childHeight * (1 - child.AnchorPoint.Y))
			end
		end
	end
	return bottom
end

local function observeGroup(janitor: Janitor.Janitor, group: GuiObject?, update: () -> ()): ()
	if not group then
		return
	end

	janitor:Add(group:GetAttributeChangedSignal("HomePosition"):Connect(update), "Disconnect")
	janitor:Add(group:GetPropertyChangedSignal("Size"):Connect(update), "Disconnect")
	janitor:Add(group:GetPropertyChangedSignal("AnchorPoint"):Connect(update), "Disconnect")
	janitor:Add(group:GetPropertyChangedSignal("Visible"):Connect(update), "Disconnect")

	local parent = group.Parent
	if not parent or not parent:IsA("GuiObject") then
		return
	end

	janitor:Add(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(update), "Disconnect")
	janitor:Add(parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(update), "Disconnect")
end

local function observeChildren(janitor: Janitor.Janitor, group: GuiObject, update: () -> ()): ()
	local cleanups: { [GuiObject]: () -> () } = {}
	local function added(child: Instance): ()
		if not child:IsA("GuiObject") then
			return
		end
		local owner = Janitor.new()
		cleanups[child] = function(): ()
			owner:Destroy()
		end
		for _, property in { "Position", "Size", "AnchorPoint", "Visible" } do
			owner:Add(child:GetPropertyChangedSignal(property):Connect(update), "Disconnect")
		end
		update()
	end
	janitor:Add(group.ChildAdded:Connect(added), "Disconnect")
	janitor:Add(group.ChildRemoved:Connect(function(child: Instance): ()
		local cleanup = if child:IsA("GuiObject") then cleanups[child] else nil
		if cleanup then
			cleanup()
			cleanups[child :: GuiObject] = nil
		end
		update()
	end), "Disconnect")
	janitor:Add(function(): ()
		for _, cleanup in cleanups do
			cleanup()
		end
		table.clear(cleanups)
	end, true)
	for _, child in group:GetChildren() do
		added(child)
	end
end

--[[ Handling ]]
--
function StatusLayout.Bind(
	screen: ScreenGui,
	frame: GuiObject,
	clock: GuiObject?,
	currency: GuiObject?
): Janitor.Janitor
	local janitor = Janitor.new()
	local originalDisplayOrder = screen.DisplayOrder
	screen.DisplayOrder = math.max(originalDisplayOrder, Config.DisplayOrder)
	janitor:Add(function(): ()
		screen.DisplayOrder = originalDisplayOrder
	end, true)

	local message = frame:FindFirstChild("Msg")
	prepareArtwork(frame)

	local function update(): ()
		local available = screen.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then
			return
		end

		local compact = available.X < Config.CompactWidth or available.Y < Config.CompactHeight
		local layout = if compact then Config.Compact else Config.Wide
		local scale = TextScale.Get(available)
		local width = math.min(layout.Width * scale, math.max(1, available.X - Config.EdgePadding * 2))
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Size = UDim2.fromOffset(width, layout.Height * scale)
		local top = layout.Top
		if clock then
			top = math.max(top, math.ceil(restingBottom(clock, false) - screen.AbsolutePosition.Y + Config.ClockGap))
		end
		if compact and currency and currency.Visible then
			top = math.max(top, math.ceil(restingBottom(currency, true) - screen.AbsolutePosition.Y + Config.ClockGap))
		end
		Animate.Place(frame, UDim2.new(0.5, 0, 0, top))

		if not message or not message:IsA("TextLabel") then
			return
		end

		message.AnchorPoint = Vector2.one / 2
		message.Position = UDim2.fromScale(0.5, 0.5)
		message.Size = UDim2.new(1, -layout.TextInset.X * scale, 1, -layout.TextInset.Y * scale)
		message.TextXAlignment = Enum.TextXAlignment.Center
		message.TextYAlignment = Enum.TextYAlignment.Center
		message.TextWrapped = true
		message.TextScaled = true

		local constraint = message:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			TextScale.Bound(constraint, layout.MinTextSize, layout.TextSize, scale)
		end
	end

	janitor:Add(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update), "Disconnect")
	janitor:Add(screen:GetPropertyChangedSignal("AbsolutePosition"):Connect(update), "Disconnect")
	observeGroup(janitor, clock, update)
	observeGroup(janitor, currency, update)
	if currency then
		observeChildren(janitor, currency, update)
	end
	janitor:LinkToInstance(frame)
	update()

	return janitor
end

return StatusLayout
