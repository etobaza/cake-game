--!strict
-- A transient, non-interactive overlay, independent of authored game screens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Hint)

local Surface = {}
export type View = {
	Screen: ScreenGui,
	Root: Frame,
	Focus: Frame,
	Corner: UICorner,
	Shade: UIStroke,
	Finger: Frame,
	Straight: ImageLabel,
	Bent: ImageLabel,
}

function Surface.new(parent: PlayerGui): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "HintOverlay"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.DisplayOrder = Config.DisplayOrder
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screen
	local focus = Instance.new("Frame")
	focus.Name = "Focus"
	focus.BackgroundTransparency = 1
	focus.Visible = false
	focus.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Config.CornerRadius)
	corner.Parent = focus
	local shade = Instance.new("UIStroke")
	shade.Name = "Shade"
	shade.Color = Color3.fromRGB(21, 16, 30)
	shade.Transparency = 1
	shade.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	shade.Parent = focus
	local finger = Instance.new("Frame")
	finger.Name = "Finger"
	finger.AnchorPoint = Vector2.one / 2
	finger.BackgroundTransparency = 1
	finger.Visible = false
	finger.ZIndex = 3
	finger.Parent = root
	local straight = Instance.new("ImageLabel")
	straight.Name = "Straight"
	straight.BackgroundTransparency = 1
	straight.Size = UDim2.fromScale(1, 1)
	straight.Image = Config.Images.Straight
	straight.ZIndex = 3
	straight.Parent = finger
	local bent = straight:Clone()
	bent.Name = "Bent"
	bent.Image = Config.Images.Bent
	bent.Parent = finger
	-- None of these objects can capture clicks or interfere with mobile movement.
	for _, object in screen:GetDescendants() do
		if object:IsA("GuiObject") then
			object.Active, object.Selectable = false, false
		end
	end
	screen.Parent = parent
	return {
		Screen = screen,
		Root = root,
		Focus = focus,
		Corner = corner,
		Shade = shade,
		Finger = finger,
		Straight = straight,
		Bent = bent,
	}
end

return Surface
