--!strict
-- The guide's speech bubble: the mentor at the bottom of the screen, above the hotbar, whose
-- bubble stays up for as long as its step is active. The step title types out letter by letter,
-- `{word}` in copy is drawn in the emphasis colour, the bubble moves to the top when it would
-- cover its own target, and a finished step shows a Done! stamp before the next one replaces it.
-- Generated in code like the other overlays (FeedbackHandler); it never touches authored screens.

--[[ Services ]]--
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")

--[[ Modules ]]--
local CatsConfig = require(ReplicatedStorage.Shared.Configs.Cats)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local Ease = require(script.Parent.Parent.Ease)
local FoodPreview = require(script.Parent.Parent.FoodPreview)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Press = require(script.Parent.Parent.Press)
local Recipes = require(ReplicatedStorage.Shared.Configs.Registries.Recipes)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(ReplicatedStorage.Shared.GameTypes)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Constants ]]--
local STYLE = Config.Dialog
local COLORS = STYLE.Colors
local PORTRAIT = STYLE.Portrait
local FONT = Theme.Fonts.ExtraBold
local HINT_FONT = Theme.Fonts.Bold
local HOTBAR_PATH = "Hotbar"
local CLOCK_PATH = "Time"
-- The plate and the progress badge straddle the bubble's top edge; this share of the plate sits
-- inside the bubble and pushes the text down.
local PLATE_INSIDE = 0.35
local POP_STRENGTH = 1.6
-- The appear pop starts from this scale.
local APPEAR_FROM = 0.55
-- Wide enough that one line never wraps while its natural width is measured.
local UNWRAPPED_WIDTH = 100000
-- Extra pixels beside a snug line, so rounding never wraps its last word.
local SNUG_SLACK = 6
-- The Done! stamp pops during this share of its time on screen.
local DONE_POP_SHARE = 0.6
local SENTENCE_MARKS = { ["."] = true, ["!"] = true, ["?"] = true, ["…"] = true }
local CLAUSE_MARKS = { [","] = true, [";"] = true, [":"] = true }

--[[ Types ]]--
type Content = {
	Key: string,
	Goal: Types.TutorialGoal,
	Title: string,
	Hint: string,
	Chars: { string },
	TitleLength: number,
	Progress: string?,
	Button: string?,
	Mood: string,
}

type View = {
	Screen: ScreenGui,
	Root: Frame,
	Scale: UIScale,
	Pop: UIScale,
	Portrait: Frame?,
	PortraitScale: UIScale?,
	-- The mood artwork when the mentor is drawn from images rather than a model.
	Face: ImageLabel?,
	Bubble: Frame,
	Shadow: Frame,
	-- The new-line "boing" scales both, so the shadow stays under the bubble.
	BubbleScale: UIScale,
	ShadowScale: UIScale,
	Plate: TextLabel,
	Badge: TextLabel,
	Done: TextLabel,
	DoneScale: UIScale,
	Title: TextLabel,
	Hint: TextLabel,
	Item: Frame,
	ItemIcon: ImageLabel,
	Button: TextButton,
	-- The typing voice, when Voice.Id is set: one sound restarted per letter.
	Voice: Sound?,
}

--[[ Tables ]]--
local Dialog = {}
Dialog.__index = Dialog

export type Dialog = typeof(setmetatable(
	{} :: {
		Janitor: any,
		View: View,
		Acknowledge: (string) -> (),
		Current: Content?,
		Pending: Content?,
		ShownAt: number,
		DoneUntil: number,
		Typed: number,
		TypeClock: number,
		Measured: string,
		Measuring: string,
		-- Measured copy: wrapped heights at the widest text width, and the unwrapped line width.
		Heights: { Title: number, Hint: number, Width: number, Line: number },
		Wanted: boolean,
		-- When the last Hide arrived; a step that returns within the grace keeps the bubble up.
		HideAt: number?,
		Shown: number,
		LayoutWidth: number,
		HopAt: number,
		-- When the current line was presented; drives the bubble's boing.
		ChangedAt: number,
		Y: number?,
		Avoid: Rect?,
	},
	Dialog
))

--[[ Private Functions ]]--
local function hex(color: Color3): string
	local function channel(value: number): number
		return math.floor(value * 255 + 0.5)
	end
	return string.format("#%02X%02X%02X", channel(color.R), channel(color.G), channel(color.B))
end

local function plain(text: string): string
	return (string.gsub(text, "[{}]", ""))
end

-- Escapes rich-text markup in authored copy, then colours every `{word}`.
local function markup(text: string): string
	local escaped = string.gsub(text, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	local colour = hex(COLORS.Emphasis)
	return (string.gsub(escaped, "{(.-)}", `<font color="{colour}">%1</font>`))
end

local function characters(text: string): { string }
	local list = {}
	for _, code in utf8.codes(text) do
		table.insert(list, utf8.char(code))
	end
	return list
end

local function corner(parent: Instance, radius: number): UICorner
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
	return object
end

local function stroke(parent: Instance, thickness: number, border: boolean): UIStroke
	local object = Instance.new("UIStroke")
	object.Color = COLORS.Ink
	object.Thickness = thickness
	object.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	object.Parent = parent
	return object
end

local function label(parent: Instance, name: string, font: Font, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextWrapped = true
	text.RichText = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = ""
	text.Parent = parent
	return text
end

local function pill(parent: Instance, name: string, fill: Color3): TextLabel
	local plate = label(parent, name, FONT, STYLE.PlateTextSize, Color3.new(1, 1, 1))
	plate.RichText = false
	plate.TextWrapped = false
	plate.AnchorPoint = Vector2.new(0, 0.5)
	plate.AutomaticSize = Enum.AutomaticSize.X
	plate.Size = UDim2.fromOffset(0, STYLE.PlateHeight)
	plate.BackgroundTransparency = 0
	plate.BackgroundColor3 = fill
	plate.TextXAlignment = Enum.TextXAlignment.Center
	plate.TextYAlignment = Enum.TextYAlignment.Center
	plate.ZIndex = 8
	corner(plate, math.floor(STYLE.PlateHeight / 2))
	stroke(plate, STYLE.Stroke, true)
	-- The white lettering gets a thin ink outline of its own.
	stroke(plate, 1.5, false)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = plate
	return plate
end

local function portraitHolder(parent: Frame, size: number): (Frame, UIScale)
	local holder = Instance.new("Frame")
	holder.Name = "Portrait"
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.fromScale(0, 1)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 10
	holder.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	return holder, scale
end

-- The mentor drawn from its mood images (Portrait.Images); every mood shares one framing, so a
-- swap never makes it jump.
local function buildFace(parent: Frame): (Frame, UIScale, ImageLabel)
	local holder, scale = portraitHolder(parent, PORTRAIT.ImageSize)
	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 1)
	face.Position = UDim2.fromScale(0.5, 1)
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.ScaleType = Enum.ScaleType.Fit
	face.Image = PORTRAIT.Images.Neutral
	face.ZIndex = 10
	face.Parent = holder
	-- Every mood is requested up front, so the first swap does not flash an empty frame.
	local list = {}
	for _, image in PORTRAIT.Images do
		if image ~= "" then
			local preload = Instance.new("ImageLabel")
			preload.Image = image
			table.insert(list, preload)
		end
	end
	task.spawn(function(): ()
		pcall(function(): ()
			ContentProvider:PreloadAsync(list)
		end)
		for _, preload in list do
			preload:Destroy()
		end
	end)
	return holder, scale, face
end

-- The fallback mentor: a cat model from the authored templates, idling in its own little world.
local function buildPortrait(parent: Frame, janitor: any): (Frame?, UIScale?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local folder = models and models:FindFirstChild(PORTRAIT.Template)
	local template = folder and folder:FindFirstChildWhichIsA("Model")
	if not template then
		print(`[TutorialDialog] Assets.Models.{PORTRAIT.Template} has no model; the guide speaks without a portrait`)
		return nil, nil
	end

	local holder, scale = portraitHolder(parent, PORTRAIT.Size)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "View"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(200, 190, 180)
	viewport.LightColor = Color3.fromRGB(255, 244, 228)
	viewport.LightDirection = Vector3.new(-1, -1.5, -1)
	viewport.ZIndex = 10
	viewport.Parent = holder
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local cat = template:Clone()
	cat.Parent = world

	local camera = Instance.new("Camera")
	camera.FieldOfView = PORTRAIT.FieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	-- The face looks away from the body's centre along the head bone; the camera sits in front of
	-- it, turned a little to show the cat in three-quarter view.
	local frame = cat:GetBoundingBox()
	local bone = cat:FindFirstChild(PORTRAIT.FocusBone, true)
	local head = if bone and bone:IsA("Bone") then bone.WorldPosition else frame.Position
	local facing = (head - frame.Position) * Vector3.new(1, 0, 1)
	local front = if facing.Magnitude > 1e-3 then facing.Unit else frame.LookVector
	front = CFrame.Angles(0, math.rad(PORTRAIT.Yaw), 0):VectorToWorldSpace(front)
	local focus = head - Vector3.new(0, PORTRAIT.FocusDrop, 0)
	local eye = focus + front * PORTRAIT.Distance + Vector3.new(0, PORTRAIT.Lift, 0)
	camera.CFrame = CFrame.lookAt(eye, focus)

	local animator = cat:FindFirstChildWhichIsA("Animator", true)
	local idle = CatsConfig.Animations.Idle
	if animator and idle then
		local animation = Instance.new("Animation")
		animation.AnimationId = idle
		local ok, track = pcall(function(): AnimationTrack
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			track:Play()
			janitor:Add(track, "Stop")
		end
		animation:Destroy()
	end
	return holder, scale
end

local function build(janitor: any): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "TutorialDialog"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.DisplayOrder = STYLE.DisplayOrder
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	janitor:Add(screen, "Destroy")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(STYLE.Width, STYLE.MinBubbleHeight)
	root.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = root
	-- The appear pop scales a child of the root, so it never fights the viewport scale.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = root
	local pop = Instance.new("UIScale")
	pop.Parent = body

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(1, 1)
	bubble.Position = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = COLORS.FillTop
	bubble.ZIndex = 4
	bubble.Parent = body
	corner(bubble, STYLE.Corner)
	stroke(bubble, STYLE.Stroke, true)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(COLORS.FillTop, COLORS.FillBottom)
	gradient.Parent = bubble
	local bubbleScale = Instance.new("UIScale")
	bubbleScale.Parent = bubble

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(1, 1)
	shadow.BackgroundColor3 = COLORS.Shadow
	shadow.BackgroundTransparency = STYLE.ShadowTransparency
	shadow.ZIndex = 2
	shadow.Parent = body
	corner(shadow, STYLE.Corner + STYLE.Stroke)
	local shadowScale = Instance.new("UIScale")
	shadowScale.Parent = shadow

	local title = label(bubble, "Title", FONT, STYLE.TitleSize, COLORS.Ink)
	title.ZIndex = 6
	local hint = label(bubble, "Hint", HINT_FONT, STYLE.HintSize, COLORS.Hint)
	hint.ZIndex = 6

	local plate = pill(bubble, "Speaker", COLORS.Plate)
	plate.Position = UDim2.fromOffset(STYLE.Padding.X, 0)
	plate.Text = string.upper(STYLE.SpeakerName)
	local badge = pill(bubble, "Progress", COLORS.Ink)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -STYLE.Padding.X, 0, 0)
	local done = pill(bubble, "Done", COLORS.Done)
	done.AnchorPoint = Vector2.new(1, 0.5)
	done.Position = UDim2.new(1, -STYLE.Padding.X, 0, 0)
	done.Text = "✓ " .. STYLE.DoneText
	done.ZIndex = 9
	done.Visible = false
	local doneScale = Instance.new("UIScale")
	doneScale.Parent = done

	local item = Instance.new("Frame")
	item.Name = "Item"
	item.AnchorPoint = Vector2.new(1, 0.5)
	item.Size = UDim2.fromOffset(STYLE.ItemSize, STYLE.ItemSize)
	item.BackgroundColor3 = Color3.new(1, 1, 1)
	item.ZIndex = 6
	item.Visible = false
	item.Parent = bubble
	corner(item, 14)
	stroke(item, 2, true)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.86, 0.86)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 7
	icon.Parent = item

	local button = Instance.new("TextButton")
	button.Name = "Acknowledge"
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromOffset(0, STYLE.ButtonHeight)
	button.BackgroundColor3 = COLORS.Button
	button.FontFace = FONT
	button.TextSize = STYLE.ButtonTextSize
	button.TextColor3 = Color3.new(1, 1, 1)
	button.ZIndex = 7
	button.Visible = false
	button.Parent = bubble
	corner(button, 10)
	stroke(button, 2, true)
	local buttonPadding = Instance.new("UIPadding")
	buttonPadding.PaddingLeft = UDim.new(0, 16)
	buttonPadding.PaddingRight = UDim.new(0, 16)
	buttonPadding.Parent = button

	-- Like BattlesOfEmpires' text voice: one reusable sound, restarted on every letter, so letters
	-- never stack into a loud chatter.
	local voice: Sound? = nil
	if STYLE.Voice.Id ~= "" then
		local created = Instance.new("Sound")
		created.Name = "TutorialVoice"
		created.SoundId = STYLE.Voice.Id
		created.Volume = STYLE.Voice.Volume
		created.Parent = SoundService
		janitor:Add(created, "Destroy")
		voice = created
	end

	local portrait: Frame?, portraitScale: UIScale?, face: ImageLabel? = nil, nil, nil
	if PORTRAIT.Images.Neutral ~= "" then
		portrait, portraitScale, face = buildFace(body)
	else
		portrait, portraitScale = buildPortrait(body, janitor)
	end
	plate.Text = string.upper(if face then PORTRAIT.Name else STYLE.SpeakerName)
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	return {
		Screen = screen,
		Root = root,
		Scale = scale,
		Pop = pop,
		Portrait = portrait,
		PortraitScale = portraitScale,
		Face = face,
		Bubble = bubble,
		Shadow = shadow,
		BubbleScale = bubbleScale,
		ShadowScale = shadowScale,
		Plate = plate,
		Badge = badge,
		Done = done,
		DoneScale = doneScale,
		Title = title,
		Hint = hint,
		Item = item,
		ItemIcon = icon,
		Button = button,
		Voice = voice,
	}
end

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, STYLE.ReferenceHeight)
end

local function uiScale(viewport: Vector2): number
	return math.clamp(viewport.Y / STYLE.ReferenceHeight, STYLE.MinScale, STYLE.MaxScale)
end

-- Reference width of the whole dialog for this viewport.
local function dialogWidth(viewport: Vector2, scale: number): number
	return math.floor(math.clamp(viewport.X / scale * STYLE.WidthRatio, STYLE.MinWidth, STYLE.Width))
end

-- Screen Y of a HUD element's top or bottom edge, in this overlay's (inset-ignoring) space.
local function hudEdge(path: string, bottom: boolean): number?
	local found, element = pcall(function(): Instance
		return UIHandler:GetHud(path)
	end)
	if not found or not element:IsA("GuiObject") or not element.Visible then
		return nil
	end
	local screen = element:FindFirstAncestorWhichIsA("ScreenGui")
	local inset = if screen and not screen.IgnoreGuiInset then GuiService:GetGuiInset().Y else 0
	local y = element.AbsolutePosition.Y + inset
	return if bottom then y + element.AbsoluteSize.Y else y
end

-- Unwrapped width of one line of copy.
local function lineWidth(text: string, font: Font, size: number): number
	if text == "" then
		return 0
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = UNWRAPPED_WIDTH
	params.RichText = true
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextBoundsAsync(params)
	end)
	return if ok then math.ceil(bounds.X) else UNWRAPPED_WIDTH
end

local function measure(text: string, font: Font, size: number, width: number): number
	if text == "" then
		return 0
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = width
	params.RichText = true
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextBoundsAsync(params)
	end)
	return if ok then math.ceil(bounds.Y) else math.ceil(size * 1.25)
end

-- Which mood the mentor shows for a step: a table of goal ids first, then urgent and recovery
-- steps, then the plain default.
local function moodFor(goal: Types.TutorialGoal): string
	local moods = PORTRAIT.Moods
	local exact = moods.ById[goal.id]
	if exact then
		return exact
	end
	for prefix, mood in moods.ByPrefix do
		if string.sub(goal.id, 1, #prefix) == prefix then
			return mood
		end
	end
	if goal.urgent then
		return moods.Urgent
	end
	if goal.recovery then
		return moods.Recovery
	end
	return moods.Default
end

local function hasItem(goal: Types.TutorialGoal): boolean
	return goal.recipeId ~= nil or (goal.itemId ~= nil and goal.itemKind ~= nil)
end

local function showItem(icon: ImageLabel, goal: Types.TutorialGoal): ()
	local recipe = goal.recipeId and Recipes:Get(goal.recipeId)
	if recipe then
		FoodPreview.Show(icon, recipe)
	elseif goal.itemId and goal.itemKind then
		FoodPreview.ShowItem(icon, { Kind = goal.itemKind, Id = goal.itemId } :: any)
	else
		FoodPreview.ShowItem(icon, nil)
	end
end

--[[ Handling ]]--
function Dialog.new(acknowledge: (string) -> ()): Dialog
	local janitor = Janitor.new()
	local view = build(janitor)
	local self = setmetatable({
		Janitor = janitor,
		View = view,
		Acknowledge = acknowledge,
		Current = nil,
		Pending = nil,
		ShownAt = 0,
		DoneUntil = 0,
		Typed = 0,
		TypeClock = 0,
		Measured = "",
		Measuring = "",
		Heights = { Title = 0, Hint = 0, Width = 0, Line = 0 },
		Wanted = false,
		HideAt = nil,
		Shown = 0,
		LayoutWidth = 0,
		HopAt = -math.huge,
		ChangedAt = -math.huge,
		Y = nil,
		Avoid = nil,
	}, Dialog) :: Dialog

	janitor:Add(
		view.Button.Activated:Connect(function(): ()
			local current = self.Current
			if current then
				self.Acknowledge(current.Goal.id)
			end
		end),
		"Disconnect"
	)
	-- A tap on the bubble finishes the typing at once.
	janitor:Add(
		view.Bubble.InputBegan:Connect(function(input: InputObject): ()
			local current = self.Current
			if current and Press.IsClick(input) then
				self.Typed = #current.Chars
			end
		end),
		"Disconnect"
	)
	janitor:Add(Press.SinkUnlessMouse(view.Bubble), "Destroy")
	janitor:Add(
		RunService.RenderStepped:Connect(function(deltaTime: number): ()
			self:Step(deltaTime)
		end),
		"Disconnect"
	)
	return self
end

--- Shows `goal` in the bubble. A different step waits until the current one has been readable
--- for `MinShowSeconds` and, when the current one was an action the player finished, its Done!
--- stamp has played.
function Dialog.Show(self: Dialog, goal: Types.TutorialGoal, progress: string?): ()
	self.Wanted = true
	self.HideAt = nil
	local title = goal.title
	-- One short line reads at a glance; the longer hint stays in the goal data for later use.
	local hint = if STYLE.ShowHint then goal.hint else ""
	local button = STYLE.Acknowledge[goal.id]
	local key = `{goal.id}|{title}|{hint}|{progress or ""}|{button or ""}|{goal.recipeId or goal.itemId or ""}`
	local current = self.Current
	if current and current.Key == key then
		current.Goal = goal
		self.Pending = nil
		return
	end
	if self.Pending and self.Pending.Key == key then
		return
	end
	local titlePlain = plain(title)
	local content: Content = {
		Key = key,
		Goal = goal,
		Title = markup(title),
		Hint = markup(hint),
		Chars = characters(titlePlain .. plain(hint)),
		TitleLength = utf8.len(titlePlain) or #titlePlain,
		Progress = progress,
		Button = button,
		Mood = moodFor(goal),
	}
	-- The same step with new wording (a live count, a seat number) redraws without the stamp.
	if not current or self.Shown < 1 or current.Goal.id == goal.id then
		self:Present(content, current ~= nil and current.Goal.id == goal.id)
		return
	end
	self.Pending = content
end

-- Steps hand over through a frame or two without a goal; the bubble only leaves once no step has
-- returned within `HideGrace`, so the Done! stamp still plays between them.
function Dialog.Hide(self: Dialog): ()
	if self.Wanted and not self.HideAt then
		self.HideAt = os.clock()
	end
end

--- A GUI rectangle (screen pixels) the bubble must not cover, usually its own target.
function Dialog.SetAvoid(self: Dialog, rect: Rect?): ()
	self.Avoid = rect
end

function Dialog.Present(self: Dialog, content: Content, instant: boolean): ()
	local previous = self.Current
	self.Current = content
	self.Pending = nil
	self.ShownAt = os.clock()
	if not instant then
		self.ChangedAt = self.ShownAt
	end
	self.TypeClock = 0
	self.Typed = if instant and previous then #content.Chars else 0
	self.Measured = ""
	local view = self.View
	view.Title.Text = content.Title
	view.Hint.Text = content.Hint
	view.Title.MaxVisibleGraphemes = 0
	view.Hint.MaxVisibleGraphemes = 0
	self:SetMood(content.Mood)
	view.Badge.Text = content.Progress or ""
	view.Badge.Visible = content.Progress ~= nil and os.clock() >= self.DoneUntil
	view.Button.Text = content.Button or ""
	view.Button.Visible = content.Button ~= nil
	view.Item.Visible = hasItem(content.Goal)
	if view.Item.Visible then
		showItem(view.ItemIcon, content.Goal)
	end
	self:Layout()
end

function Dialog.SetMood(self: Dialog, mood: string): ()
	local face = self.View.Face
	if not face then
		return
	end
	local image = PORTRAIT.Images[mood]
	face.Image = if image and image ~= "" then image else PORTRAIT.Images.Neutral
end

-- Measures the copy for the current width, then sizes and places every part of the bubble.
function Dialog.Layout(self: Dialog): ()
	local content = self.Current
	if not content then
		return
	end
	local view = self.View
	local viewport = viewportSize()
	local scale = uiScale(viewport)
	local widest = dialogWidth(viewport, scale)
	local portrait = if view.Portrait then view.Portrait.Size.X.Offset else 0
	local bubbleX = math.floor(portrait * PORTRAIT.BubbleStart)
	local itemSpace = if view.Item.Visible then STYLE.ItemSize + STYLE.ItemGap else 0
	-- The mentor leans over the bubble's left edge; the copy starts clear of it.
	local gap = if view.Face then PORTRAIT.ImageGap else STYLE.PortraitGap
	local textLeft = math.max(STYLE.Padding.X, portrait - bubbleX + gap)
	local chrome = bubbleX + textLeft + STYLE.Padding.X + itemSpace
	local widestText = widest - chrome
	local key = `{content.Key}@{widestText}`

	if self.Measured ~= key then
		if self.Measuring == key then
			return
		end
		self.Measuring = key
		task.spawn(function(): ()
			local titleHeight = measure(content.Title, FONT, STYLE.TitleSize, widestText)
			local hintHeight = measure(content.Hint, HINT_FONT, STYLE.HintSize, widestText)
			local line = math.max(
				lineWidth(content.Title, FONT, STYLE.TitleSize),
				lineWidth(content.Hint, HINT_FONT, STYLE.HintSize)
			)
			if self.Measuring ~= key then
				return
			end
			self.Measuring = ""
			self.Measured = key
			self.Heights = { Title = titleHeight, Hint = hintHeight, Width = widestText, Line = line }
			self:Layout()
		end)
		return
	end
	self.LayoutWidth = widest

	-- A short line gets a snug bubble (text plus its chrome); a long one wraps at the widest.
	local textWidth = math.min(widestText, self.Heights.Line + SNUG_SLACK)
	local width = math.max(STYLE.MinWidth, chrome + textWidth)
	textWidth = width - chrome
	local bubbleWidth = width - bubbleX

	local heights = self.Heights
	local top = math.ceil(STYLE.PlateHeight * PLATE_INSIDE)
	local text = heights.Title + (if heights.Hint > 0 then STYLE.LineGap + heights.Hint else 0)
	local buttonSpace = if view.Button.Visible then STYLE.LineGap * 2 + STYLE.ButtonHeight else 0
	local inner = math.max(text + buttonSpace, if view.Item.Visible then STYLE.ItemSize else 0)
	local bubbleHeight = math.max(STYLE.MinBubbleHeight, inner + STYLE.Padding.Y * 2 + top)
	local height = math.max(bubbleHeight + math.ceil(STYLE.PlateHeight / 2), portrait)

	view.Root.Size = UDim2.fromOffset(width, height)
	view.Bubble.Size = UDim2.fromOffset(bubbleWidth, bubbleHeight)
	view.Shadow.Size = UDim2.fromOffset(bubbleWidth + STYLE.Stroke * 2, bubbleHeight + STYLE.Stroke * 2)

	-- The copy sits centred beside a taller item tile.
	local textTop = STYLE.Padding.Y + top + math.floor((inner - text - buttonSpace) / 2)
	view.Plate.Position = UDim2.fromOffset(textLeft, 0)
	view.Title.Position = UDim2.fromOffset(textLeft, textTop)
	view.Title.Size = UDim2.fromOffset(textWidth, heights.Title)
	view.Hint.Position = UDim2.fromOffset(textLeft, textTop + heights.Title + STYLE.LineGap)
	view.Hint.Size = UDim2.fromOffset(textWidth, heights.Hint)
	view.Button.Position = UDim2.fromOffset(textLeft, textTop + text + STYLE.LineGap * 2)
	view.Item.Position = UDim2.new(1, -STYLE.Padding.X, 0, STYLE.Padding.Y + top + inner / 2)
end

function Dialog.Step(self: Dialog, deltaTime: number): ()
	local view = self.View
	local now = os.clock()
	local hideAt = self.HideAt
	if self.Wanted and hideAt and now - hideAt >= STYLE.HideGrace then
		self.Wanted = false
		self.HideAt = nil
		self.Pending = nil
	end
	local wanted = self.Wanted and self.Current ~= nil and not GuiService.MenuIsOpen

	-- A finished step plays its stamp once it has been readable long enough, then hands over.
	local pending = self.Pending
	if pending and wanted and now - self.ShownAt >= STYLE.MinShowSeconds then
		local current = self.Current
		local finished = current ~= nil
			and not current.Goal.waiting
			and not current.Goal.recovery
			and not pending.Goal.recovery
		if self.DoneUntil <= now and finished and not view.Done.Visible then
			self.DoneUntil = now + STYLE.DoneSeconds
			self:SetMood(PORTRAIT.Moods.Done)
			view.Done.Visible = true
			view.Badge.Visible = false
			SoundPlayer.Play("Sparkle")
		elseif self.DoneUntil <= now then
			view.Done.Visible = false
			self:Present(pending, false)
		end
	elseif pending and not wanted then
		self:Present(pending, true)
	end
	if view.Done.Visible then
		local age = STYLE.DoneSeconds - (self.DoneUntil - now)
		view.DoneScale.Scale = Ease.OutBack(age / (STYLE.DoneSeconds * DONE_POP_SHARE), POP_STRENGTH)
	end

	-- Appear with a pop; leave with a quick shrink, then switch the screen off.
	if wanted and self.Shown == 0 then
		self.Y = nil
	end
	local rate = deltaTime / (if wanted then STYLE.AppearSeconds else STYLE.ExitSeconds)
	self.Shown = math.clamp(self.Shown + (if wanted then rate else -rate), 0, 1)
	view.Screen.Enabled = self.Shown > 0
	if self.Shown <= 0 then
		return
	end
	local popped = if wanted
		then APPEAR_FROM + (1 - APPEAR_FROM) * Ease.OutBack(self.Shown, POP_STRENGTH)
		else Ease.Clamp(self.Shown)
	view.Pop.Scale = popped

	local viewport = viewportSize()
	local scale = uiScale(viewport)
	view.Scale.Scale = scale
	if self.LayoutWidth ~= dialogWidth(viewport, scale) then
		self:Layout()
	end
	self:Place(deltaTime, viewport, scale)
	self:Boing(now)
	self:Type(deltaTime, now)
end

-- Every new line gives the bubble a small hop and swell, like Lemon Cake's dialogue change.
function Dialog.Boing(self: Dialog, now: number): ()
	local view = self.View
	local boing = STYLE.Boing
	local t = Ease.Clamp((now - self.ChangedAt) / boing.Seconds)
	local wave = if t < 1 then math.sin(t * math.pi) else 0
	local grow = 1 + (boing.Scale - 1) * wave
	view.BubbleScale.Scale = grow
	view.ShadowScale.Scale = grow
	view.Bubble.Position = UDim2.new(1, 0, 1, -boing.Lift * wave)
	view.Shadow.Position =
		UDim2.new(1, STYLE.Stroke, 1, STYLE.Stroke + STYLE.ShadowDrop - boing.Lift * wave)
end

-- Bottom centre above the hotbar; at the top, below the clock, when that would cover the target.
function Dialog.Place(self: Dialog, deltaTime: number, viewport: Vector2, scale: number): ()
	local view = self.View
	local size = view.Root.Size
	local width, height = size.X.Offset * scale, size.Y.Offset * scale
	-- The HUD slides off screen while a page is open; then the plain bottom margin applies.
	local hotbar = hudEdge(HOTBAR_PATH, false)
	local onScreen = hotbar ~= nil and hotbar < viewport.Y
	local bottom = if hotbar and onScreen
		then hotbar - STYLE.HotbarGap * scale
		else viewport.Y - STYLE.BottomMargin * scale
	local avoid = self.Avoid
	local left = viewport.X / 2 - width / 2
	local covers = avoid ~= nil
		and avoid.Max.X > left
		and avoid.Min.X < left + width
		and avoid.Max.Y > bottom - height
		and avoid.Min.Y < bottom
	local goal = bottom
	if covers then
		local clock = hudEdge(CLOCK_PATH, true)
		goal = (clock or STYLE.TopFallback * scale) + STYLE.TopGap * scale + height
	end
	local last = self.Y
	local y = if last then last + (goal - last) * (1 - math.exp(-deltaTime / STYLE.MoveSmoothing)) else goal
	self.Y = y
	view.Root.Position = UDim2.fromOffset(viewport.X / 2, y)
end

function Dialog.Type(self: Dialog, deltaTime: number, now: number): ()
	local view = self.View
	local content = self.Current
	if not content or self.Measured == "" then
		return
	end
	local total = #content.Chars
	self.TypeClock += deltaTime
	while self.Typed < total do
		local previous = content.Chars[self.Typed]
		local delay = STYLE.CharSeconds
		if previous and SENTENCE_MARKS[previous] then
			delay += STYLE.SentencePause
		elseif previous and CLAUSE_MARKS[previous] then
			delay += STYLE.CommaPause
		end
		-- The title's last letter pauses like a full stop before the hint begins.
		if self.Typed == content.TitleLength then
			delay += STYLE.SentencePause
		end
		if self.TypeClock < delay then
			break
		end
		self.TypeClock -= delay
		self.Typed += 1
		local char = content.Chars[self.Typed]
		if char ~= " " then
			self.HopAt = now
		end
		-- Only letters and digits speak; spaces and punctuation stay silent.
		local voice = view.Voice
		if voice and string.find(char, "^%w$") then
			local pitch = STYLE.Voice.Pitch
			voice.PlaybackSpeed = pitch.Min + math.random() * (pitch.Max - pitch.Min)
			voice.TimePosition = 0
			voice:Play()
		end
	end
	if self.Typed >= total then
		self.TypeClock = 0
	end
	view.Title.MaxVisibleGraphemes = math.min(self.Typed, content.TitleLength)
	view.Hint.MaxVisibleGraphemes = math.max(0, self.Typed - content.TitleLength)

	local portrait = view.Portrait
	local portraitScale = view.PortraitScale
	if portrait and portraitScale then
		local breath = math.sin(now * 2 * math.pi / PORTRAIT.BreathPeriod)
		portraitScale.Scale = 1 + PORTRAIT.BreathScale * breath
		local hop = Ease.Clamp((now - self.HopAt) / PORTRAIT.HopSeconds)
		local lift = if hop < 1 then math.sin(hop * math.pi) * PORTRAIT.HopPixels else 0
		-- A ghost floats: a slow bob and sway on top of the talking hop.
		local float = PORTRAIT.Float
		local phase = now * 2 * math.pi / float.Period
		lift += math.sin(phase) * float.Pixels
		portrait.Rotation = PORTRAIT.Tilt + math.sin(phase * 0.5) * float.Sway
		portrait.Position = UDim2.new(0, 0, 1, -lift)
	end
end

function Dialog.Destroy(self: Dialog): ()
	FoodPreview.Clear(self.View.ItemIcon)
	self.Janitor:Destroy()
	self.Current = nil
	self.Pending = nil
end

return Dialog
