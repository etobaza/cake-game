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
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Constants ]]--
local GUI_NAME = "LiveEventBanner"
local HEADSHOT_SIZE = 64
local PADDING = 10
local CORNER = UDim.new(0, 14)
local CARD_COLOR = Color3.fromRGB(40, 26, 22)
local CARD_TRANSPARENCY = 0.15
local MUTED_TEXT = Color3.fromRGB(230, 214, 196)
local LINE_POP_FROM = 0.92

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

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = hud.Position
	card.Size = UDim2.new(1, -32, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CARD_COLOR
	card.BackgroundTransparency = CARD_TRANSPARENCY
	card.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(hud.Width, math.huge)
	constraint.Parent = card
	local corner = Instance.new("UICorner")
	corner.CornerRadius = CORNER
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = hud.Accent
	stroke.Thickness = 2
	stroke.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING)
	padding.PaddingBottom = UDim.new(0, PADDING)
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = card
	list(card, Enum.FillDirection.Vertical, 8)

	local status = label(card, "Status", Theme.Fonts.Bold, 16, 1)
	status.TextColor3 = hud.Accent

	local row = Instance.new("Frame")
	row.Name = "Line"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = 2
	row.Visible = false
	row.Parent = card
	list(row, Enum.FillDirection.Horizontal, PADDING)

	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.Size = UDim2.fromOffset(HEADSHOT_SIZE, HEADSHOT_SIZE)
	headshot.BackgroundColor3 = hud.Accent
	headshot.LayoutOrder = 1
	headshot.Parent = row
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = headshot

	local column = Instance.new("Frame")
	column.Name = "Words"
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(1, -(HEADSHOT_SIZE + PADDING), 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.LayoutOrder = 2
	column.Parent = row
	list(column, Enum.FillDirection.Vertical, 2)

	local name = label(column, "Name", Theme.Fonts.ExtraBold, 20, 1)
	local role = label(column, "Role", Theme.Fonts.SemiBold, 14, 2)
	role.TextColor3 = MUTED_TEXT
	local text = label(column, "Text", Theme.Fonts.Bold, 18, 3)

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
	}, Banner)
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
	Animate.Pop(self.Card, LINE_POP_FROM)
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
	},
	Banner
))

return Banner
