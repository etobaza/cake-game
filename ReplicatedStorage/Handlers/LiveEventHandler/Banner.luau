--!strict
-- Live event HUD banner: a status row (countdown or time left) and, while someone speaks, their
-- headshot, display name, role and line. A generated overlay like BuildLabel: it belongs to no
-- authored screen, takes no input and only exists while an event is announced or running.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Animate = require(ReplicatedStorage.Shared.UI.Animate)
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local TextScale = require(ReplicatedStorage.Shared.UI.TextScale)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Constants ]]--
local GUI_NAME = "LiveEventBanner"

--[[ Tables ]]--
local Banner = {}
Banner.__index = Banner

--[[ Private Functions ]]--
local function label(parent: Instance, name: string, font: Font, size: number, order: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = Theme.Colors.TextFace
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextWrapped = true
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.Size = UDim2.fromScale(1, 0)
	text.LayoutOrder = order
	text.Parent = parent
	return text
end

local function list(parent: Instance, direction: Enum.FillDirection, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
	return layout
end

local function formatTime(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

--[[ Handling ]]--
function Banner.new(): Banner
	local hud = Config.Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = hud.DisplayOrder
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Placed and sized by Layout.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = hud.CardColor
	card.BackgroundTransparency = hud.CardTransparency
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, hud.CornerRadius)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = hud.Accent
	stroke.Thickness = hud.StrokeThickness
	stroke.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, hud.Padding)
	padding.PaddingBottom = UDim.new(0, hud.Padding)
	padding.PaddingLeft = UDim.new(0, hud.Padding)
	padding.PaddingRight = UDim.new(0, hud.Padding)
	padding.Parent = card
	list(card, Enum.FillDirection.Vertical, 8)

	local status = label(card, "Status", Theme.Fonts.Bold, hud.TextSizes.Status, 1)
	status.TextColor3 = hud.Accent

	local row = Instance.new("Frame")
	row.Name = "Line"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = 2
	row.Visible = false
	row.Parent = card
	list(row, Enum.FillDirection.Horizontal, hud.Padding)

	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.Size = UDim2.fromOffset(hud.HeadshotSize, hud.HeadshotSize)
	headshot.BackgroundColor3 = hud.Accent
	headshot.LayoutOrder = 1
	headshot.Parent = row
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = headshot

	local column = Instance.new("Frame")
	column.Name = "Words"
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(1, -(hud.HeadshotSize + hud.Padding), 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.LayoutOrder = 2
	column.Parent = row
	list(column, Enum.FillDirection.Vertical, 2)

	local name = label(column, "Name", Theme.Fonts.ExtraBold, hud.TextSizes.Name, 1)
	local role = label(column, "Role", Theme.Fonts.SemiBold, hud.TextSizes.Role, 2)
	role.TextColor3 = hud.RoleColor
	local text = label(column, "Text", Theme.Fonts.Bold, hud.TextSizes.Line, 3)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	return setmetatable({
		Gui = gui,
		Card = card,
		Status = status,
		Row = row,
		Headshot = headshot,
		Name = name,
		Role = role,
		Text = text,
		Scale = 0,
		TextSizes = {
			[status] = hud.TextSizes.Status,
			[name] = hud.TextSizes.Name,
			[role] = hud.TextSizes.Role,
			[text] = hud.TextSizes.Line,
		},
	}, Banner)
end

--- Centres the card just below absolute row `top`, at the screen's density.
function Banner.Layout(self: Banner, top: number): ()
	local hud = Config.Hud
	local area = self.Gui.AbsoluteSize
	local scale = TextScale.Screen(area)
	self.Card.Position = UDim2.new(0.5, 0, 0, top - self.Gui.AbsolutePosition.Y)
	self.Card.Size = UDim2.fromOffset(math.min(hud.Width, (area.X - hud.SideMargin * 2) / scale), 0)
	if scale == self.Scale then
		return
	end
	self.Scale = scale
	Animate.SetLayoutScale(self.Card, scale)
	for line, size in self.TextSizes do
		line.TextSize = math.max(size, Theme.ScreenScale.MinTextPixels / scale)
	end
end

function Banner.ShowCountdown(self: Banner, seconds: number): ()
	self.Gui.Enabled = true
	self.Row.Visible = false
	self.Status.Text = `{Config.Hud.Title} • {string.format(Config.Hud.StartingText, math.ceil(seconds))}`
end

function Banner.ShowLive(self: Banner, secondsLeft: number): ()
	self.Gui.Enabled = true
	self.Status.Text = `{Config.Hud.Title} • {string.format(Config.Hud.LiveText, formatTime(secondsLeft))}`
end

function Banner.ShowLine(self: Banner, castId: string, name: string, text: string): ()
	local member = Config.Cast[castId]
	self.Headshot.Image = `rbxthumb://type=AvatarHeadShot&id={member.UserId}&w=150&h=150`
	self.Name.Text = name
	self.Role.Text = member.Role
	self.Text.Text = text
	self.Row.Visible = true
	Animate.Pop(self.Card, Config.Hud.LinePopFrom)
end

function Banner.ClearLine(self: Banner): ()
	self.Row.Visible = false
end

function Banner.Hide(self: Banner): ()
	self.Gui.Enabled = false
	self.Row.Visible = false
end

function Banner.Destroy(self: Banner): ()
	self.Gui:Destroy()
end

export type Banner = typeof(setmetatable(
	{} :: {
		Gui: ScreenGui,
		Card: Frame,
		Status: TextLabel,
		Row: Frame,
		Headshot: ImageLabel,
		Name: TextLabel,
		Role: TextLabel,
		Text: TextLabel,
		-- Density of the last layout, and each label's configured logical text size.
		Scale: number,
		TextSizes: { [TextLabel]: number },
	},
	Banner
))

return Banner
