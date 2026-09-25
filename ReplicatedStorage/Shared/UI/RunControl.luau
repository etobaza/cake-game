--!strict
-- Fits the authored sprint button beside the live Roblox touch jump control.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Configs.TouchControls)
local Janitor = require(ReplicatedStorage.Packages.janitor)

local RunControl = {}

function RunControl.SetRunning(button: TextButton, running: boolean): ()
	button.Text = if running then "Walk" else "Run"
	button.BackgroundColor3 = if running then Config.Light else Config.Dark
	button.BackgroundTransparency = if running then Config.ActiveTransparency else Config.IdleTransparency
	button.TextColor3 = if running then Config.Dark else Config.Light
	button.TextTransparency = if running then 0 else Config.IdleTransparency
end

function RunControl.Bind(button: TextButton, playerGui: PlayerGui): Janitor.Janitor
	local janitor = Janitor.new()
	local jumpJanitor = Janitor.new()
	janitor:Add(jumpJanitor, "Destroy")
	local parent = button.Parent
	assert(parent and parent:IsA("GuiObject"), "[RunControl] Run requires a GUI container")
	local container = parent :: GuiObject
	local jump: GuiObject? = nil

	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.AnchorPoint = Vector2.one / 2
	button.Font = Enum.Font.GothamBold
	button.TextScaled = false
	button.TextStrokeTransparency = 1
	local corner = button:FindFirstChildOfClass("UICorner")
	local stroke = button:FindFirstChildOfClass("UIStroke")
	assert(corner and stroke, "[RunControl] Run requires its authored corner and stroke")
	corner.CornerRadius = UDim.new(0.5, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Config.Light
	stroke.Transparency = Config.IdleTransparency
	RunControl.SetRunning(button, false)
	button:SetAttribute("TouchLayoutReady", false)

	local function update(): ()
		local target = jump
		local bounds = container.AbsoluteSize
		if not target or not target:IsDescendantOf(playerGui) or bounds.X <= 0 or bounds.Y <= 0 then
			button:SetAttribute("TouchLayoutReady", false)
			return
		end
		local size = target.AbsoluteSize
		local side = math.min(size.X, size.Y)
		if side <= 0 then
			button:SetAttribute("TouchLayoutReady", false)
			return
		end
		local center = target.AbsolutePosition + size / 2 - container.AbsolutePosition
		local offset = side + Config.Gap
		-- Phones keep the central hotbar free; tablets have room for a horizontal pair.
		center -= if side <= Config.SmallButtonThreshold then Vector2.new(0, offset) else Vector2.new(offset, 0)
		local diameter = side * Config.VisibleDiameter
		button.Size = UDim2.fromScale(diameter / bounds.X, diameter / bounds.Y)
		button.Position = UDim2.fromScale(center.X / bounds.X, center.Y / bounds.Y)
		stroke.Thickness = side * Config.RingThickness
		button.TextSize = side * Config.TextSize
		local touchGui = target:FindFirstAncestorWhichIsA("ScreenGui")
		local targetParent = target.Parent
		button:SetAttribute(
			"TouchLayoutReady",
			target.Visible
				and touchGui ~= nil
				and touchGui.Enabled
				and targetParent ~= nil
				and targetParent:IsA("GuiObject")
				and targetParent.Visible
		)
	end

	local function findJump(): ()
		local touchGui = playerGui:FindFirstChild("TouchGui")
		local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
		local candidate = frame and frame:FindFirstChild("JumpButton")
		local found = if candidate and candidate:IsA("GuiObject") then candidate else nil
		if found == jump then
			update()
			return
		end
		jumpJanitor:Cleanup()
		jump = found
		if found then
			for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
				jumpJanitor:Add(found:GetPropertyChangedSignal(property):Connect(update), "Disconnect")
			end
			jumpJanitor:Add(found.AncestryChanged:Connect(findJump), "Disconnect")
			if touchGui and touchGui:IsA("ScreenGui") then
				jumpJanitor:Add(touchGui:GetPropertyChangedSignal("Enabled"):Connect(update), "Disconnect")
			end
			if frame and frame:IsA("GuiObject") then
				jumpJanitor:Add(frame:GetPropertyChangedSignal("Visible"):Connect(update), "Disconnect")
			end
		end
		update()
	end

	janitor:Add(playerGui.DescendantAdded:Connect(function(instance: Instance): ()
		if instance.Name == "JumpButton" or instance.Name == "TouchGui" then
			findJump()
		end
	end), "Disconnect")
	janitor:Add(container:GetPropertyChangedSignal("AbsolutePosition"):Connect(update), "Disconnect")
	janitor:Add(container:GetPropertyChangedSignal("AbsoluteSize"):Connect(update), "Disconnect")
	janitor:LinkToInstance(button)
	findJump()
	return janitor
end

return RunControl
