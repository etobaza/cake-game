--!strict
-- Shows the published place version (and a short server id) in the bottom-left corner.
--
-- A generated overlay rather than an authored screen: it carries one line of text, belongs to no
-- page and must not move with any HUD layout. It never takes input.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.BuildLabel)
local TextScale = require(ReplicatedStorage.Shared.UI.TextScale)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Constants ]]--
local GUI_NAME = "BuildLabel"

--[[ Tables ]]--
local BuildLabelHandler = {
	priority = 0,
}

--[[ Private Functions ]]--
local function labelText(): string
	if RunService:IsStudio() then
		return Config.StudioText
	end

	local text = `v{game.PlaceVersion}`
	if Config.JobIdLength > 0 and game.JobId ~= "" then
		text ..= ` · {string.sub(game.JobId, 1, Config.JobIdLength)}`
	end
	return text
end

--[[ Handling ]]--
function BuildLabelHandler.OnStart(_self: BuildLabelHandler): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- ResetOnSpawn is off, so the label lives as long as the PlayerGui does.
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Config.DisplayOrder
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local label = Instance.new("TextLabel")
	label.Name = "Version"
	label.Active = false
	label.Selectable = false
	label.AnchorPoint = Vector2.new(0, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.SemiBold
	label.TextColor3 = Config.TextColor
	label.TextTransparency = Config.TextTransparency
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.Text = labelText()

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.StrokeColor
	stroke.Transparency = Config.StrokeTransparency
	stroke.Parent = label

	label.Parent = gui
	gui.Parent = playerGui

	-- The connection goes with the label's ScreenGui.
	local function layout(): ()
		local scale = TextScale.Screen(gui.AbsoluteSize)
		local textSize = math.max(Theme.ScreenScale.MinTextPixels, Config.TextSize * scale)
		local box = Config.Size * textSize / Config.TextSize
		label.TextSize = textSize
		label.Size = UDim2.fromOffset(box.X, box.Y)
		label.Position = UDim2.new(0, Config.Offset.X * scale, 1, -Config.Offset.Y * scale)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
end

export type BuildLabelHandler = typeof(BuildLabelHandler)

return BuildLabelHandler
