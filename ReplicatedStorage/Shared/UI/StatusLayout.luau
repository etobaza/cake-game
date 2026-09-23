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

--[[ Handling ]]
--
function StatusLayout.Bind(screen: ScreenGui, frame: GuiObject): Janitor.Janitor
	local janitor = Janitor.new()
	local message = frame:FindFirstChild("Msg")
	prepareArtwork(frame)

	local function update(): ()
		local available = screen.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then
			return
		end

		local compact = available.X < Config.CompactWidth or available.Y < Config.CompactHeight
		local layout = if compact then Config.Compact else Config.Wide
		local width = math.min(layout.Width, math.max(1, available.X - Config.EdgePadding * 2))
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Size = UDim2.fromOffset(width, layout.Height)
		Animate.Place(frame, UDim2.new(0.5, 0, 0, layout.Top))

		if not message or not message:IsA("TextLabel") then
			return
		end

		message.AnchorPoint = Vector2.one / 2
		message.Position = UDim2.fromScale(0.5, 0.5)
		message.Size = UDim2.new(1, -layout.TextInset.X, 1, -layout.TextInset.Y)
		message.TextXAlignment = Enum.TextXAlignment.Center
		message.TextYAlignment = Enum.TextYAlignment.Center
		message.TextWrapped = true
		message.TextScaled = true

		local constraint = message:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			constraint.MinTextSize = layout.MinTextSize
			constraint.MaxTextSize = layout.TextSize
		end
	end

	janitor:Add(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update), "Disconnect")
	janitor:LinkToInstance(frame)
	update()

	return janitor
end

return StatusLayout
