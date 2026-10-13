--!strict
-- Speech bubble over the speaking giant. A local BillboardGui sized in studs rather than
-- TextChatService:DisplayBubble: chat bubbles fade out at BubbleChatConfiguration.MaxDistance
-- (100 studs by default), and the giants stand hundreds of studs away. Raising that limit would
-- change every player's bubbles too.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

--[[ Constants ]]--
local BUBBLE_NAME = "LiveEventSpeech"
local BUBBLE_COLOR = Color3.fromRGB(255, 255, 255)
local TEXT_COLOR = Color3.fromRGB(40, 26, 22)
local TEXT_PADDING = 0.06

--[[ Tables ]]--
local Speech = {}
Speech.__index = Speech

--[[ Handling ]]--
function Speech.new(folder: Instance): Speech
	return setmetatable({ Folder = folder, Bubble = nil :: BillboardGui? }, Speech)
end

function Speech.Say(self: Speech, castId: string, text: string): ()
	self:Clear()
	local giant = self.Folder:FindFirstChild(`Cast_{castId}`)
	local head = giant and giant:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local speech = Config.Speech
	local scale = Config.Stage.Scale
	local size = speech.BubbleSize * scale
	local bubble = Instance.new("BillboardGui")
	bubble.Name = BUBBLE_NAME
	bubble.Size = UDim2.fromScale(size.X, size.Y)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + speech.BubbleOffset * scale + size.Y / 2, 0)
	bubble.LightInfluence = 0
	bubble.MaxDistance = math.huge
	bubble.Adornee = head

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = BUBBLE_COLOR
	frame.Parent = bubble
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Hud.Accent
	stroke.Thickness = 3
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1 - TEXT_PADDING * 2, 1 - TEXT_PADDING * 4)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Bold
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = TEXT_COLOR
	label.Text = text
	label.Parent = frame

	bubble.Parent = head
	self.Bubble = bubble
end

function Speech.Clear(self: Speech): ()
	local bubble = self.Bubble
	self.Bubble = nil
	if bubble then
		bubble:Destroy()
	end
end

function Speech.Destroy(self: Speech): ()
	self:Clear()
end

export type Speech = typeof(setmetatable({} :: { Folder: Instance, Bubble: BillboardGui? }, Speech))

return Speech
