--!strict
-- Custom look for every ProximityPrompt: the engine still decides when a prompt shows and what
-- pressing it does; this handler draws the artist billboard and outlines its actionable object.
--
-- The art lives in ReplicatedStorage.Assets.Prompt (place-only). Server prompts are created with
-- Style = Custom (BuildingHandler/View), so the stock UI never renders. One billboard serves every
-- prompt: our prompts share one key, so the engine shows at most one at a time.

--[[ Services ]]--
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local AmbientMotion = require(ReplicatedStorage.Handlers.AmbientMotionHandler)
local BuildingsConfig = require(_Configs.Buildings)
local CatsConfig = require(_Configs.Cats)
local InteractionHighlight = require(_Shared.InteractionHighlight)
local Interact = require(ReplicatedStorage.Handlers.InteractHandler)
local Janitor = require(_Packages.janitor)
local Flux = require(_Packages.flux)
local Pages = require(_Shared.UI.Stores.Pages)
local Press = require(_Shared.UI.Press)
local PromptConfig = require(_Configs.Prompts)
local Scope = require(_Shared.UI.Scope)
local StationStatusConfig = require(_Configs.StationStatus)
local TextScale = require(_Shared.UI.TextScale)
local WorldPose = require(_Shared.WorldPose)

--[[ Constants ]]--
local TEMPLATE_TIMEOUT = 10
-- Studs above the top of the adorned part, matching where the artist floated the sample.
local PROMPT_LIFT = 1
-- Which icon answers which input, by child name in the authored art. The art carries several
-- variants named IconE; the first one wins.
local ICON_KEYBOARD = "IconE"
local ICON_GAMEPAD = "IconX"
local ICON_TOUCH = "IconCusor"
-- What counts as a press on the plate itself. Same set Shared/UI/Press uses, for the same reason.
local PRESS_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

-- A press answers at once, before the server does: the plate punches. It stays silent, because
-- each accepted action already plays its own sound (Get, Put, Mixing...).
local PRESS_POP = 0.86
-- Moving between nearby props within this many seconds keeps the plate up and only swaps its
-- text with a small punch, instead of replaying the whole entrance.
local SWAP_SECONDS = 0.3
local SWAP_POP = 0.94
-- A status-only plate (a busy station) swaps its card for a small wooden sign
-- (funset_ui_status_plate_wood, generated with Codex in the HUD icon style) with one centred line.
local STATUS_PLATE_IMAGE = "rbxassetid://129385372765867"
local STATUS_NAME_POSITION = UDim2.fromScale(0.5, 0.5)
-- The status line's lettering: white face and a short cocoa drop shadow, without an outline.
local STATUS_FACE = Color3.fromRGB(255, 255, 255)
local STATUS_INK = Color3.fromRGB(58, 32, 22)
local STATUS_SHADOW_DROP = UDim2.fromScale(0, 0.05)

--[[ Tables ]]--
local PromptHandler = {
	-- Resolve visible garden copies and query the existing interaction policy after their owners initialize.
	dependencies = { "AmbientMotionHandler", "InteractHandler" },
}

--[[ Private Functions ]]--
local function bindLayout(billboard: BillboardGui, root: Frame): any
	local janitor = Janitor.new()
	local cameraJanitor = Janitor.new()
	janitor:Add(cameraJanitor, "Destroy")
	janitor:Add(Animate.Scale(root), "destroy")
	-- Center the scaled art on its billboard; enter/exit motion keeps the same rest point.
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	Animate.Place(root, UDim2.fromScale(0.5, 0.5))
	local holders: { [string]: { Position: UDim2, Size: UDim2 } } = {
		Name = { Position = PromptConfig.NamePosition, Size = PromptConfig.NameSize },
		Txt = { Position = PromptConfig.ActionPosition, Size = PromptConfig.ActionSize },
	}
	for name, geometry in holders do
		local holder = root:FindFirstChild(name)
		if holder and holder:IsA("GuiObject") then
			holder.Position = geometry.Position
			holder.Size = geometry.Size
		end
	end
	for _, child in root:GetChildren() do
		if child:IsA("ImageLabel") and string.sub(child.Name, 1, 4) == "Icon" then
			child.AnchorPoint = Vector2.new(0.5, 0.5)
			child.Position = PromptConfig.IconPosition
			child.Size = UDim2.fromOffset(PromptConfig.IconSize, PromptConfig.IconSize)
			child.ScaleType = Enum.ScaleType.Fit
		end
	end
	local function update(): ()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.zero
		local compact = viewport.X < PromptConfig.CompactWidth or viewport.Y < PromptConfig.CompactHeight
		local status = billboard:GetAttribute("StatusOnly") == true
		local dimensions = if status then PromptConfig.StatusSize
			else if compact then PromptConfig.CompactSize else PromptConfig.WideSize
		local scale = math.min(TextScale.Get(viewport), PromptConfig.MaximumScale)
		-- Fixed pixels preserve distance stability without inflating proximity plates on large screens.
		local width = math.min(dimensions.X * scale, math.max(1, viewport.X - PromptConfig.EdgePadding * 2))
		billboard.Size = UDim2.fromOffset(width, dimensions.Y * scale)
		local aspect = root:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect.AspectRatio = width / (dimensions.Y * scale)
		end
		Animate.SetLayoutScale(root, 1)
		local name = root:FindFirstChild("Name")
		for _, label in root:GetDescendants() do
			if not label:IsA("TextLabel") then
				continue
			end
			local nameLabel = name ~= nil and label:IsDescendantOf(name)
			local maximum = if nameLabel then (if status then PromptConfig.StatusTextSize else PromptConfig.NameTextSize)
				else PromptConfig.ActionTextSize
			label.TextWrapped = true
			label.TextScaled = true
			local constraint = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
			constraint.MinTextSize = math.floor(PromptConfig.MinTextSize * scale + 0.5)
			constraint.MaxTextSize = math.floor(maximum * scale + 0.5)
			constraint.Parent = label
		end
	end
	local function bindCamera(): ()
		cameraJanitor:Cleanup()
		local camera = workspace.CurrentCamera
		if camera then
			cameraJanitor:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(update), "Disconnect")
		end
		update()
	end
	janitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera), "Disconnect")
	janitor:Add(billboard:GetAttributeChangedSignal("StatusOnly"):Connect(update), "Disconnect")
	janitor:LinkToInstance(root)
	bindCamera()
	return janitor
end

local function canHighlight(prompt: ProximityPrompt?): boolean
	local part = prompt and prompt.Parent
	if not prompt or not prompt.Enabled or not part or not part:IsA("BasePart") then
		return false
	end
	if part.Parent and part.Parent:HasTag(CatsConfig.Tag) then
		return true
	end
	if not part:HasTag(BuildingsConfig.Tag) then
		return false
	end
	-- Some visible prompts only explain a status, such as the empty trash can.
	return Interact:Describe(part).Fire ~= nil
end

local function pickIcon(): string
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		return ICON_GAMEPAD
	end
	return if UserInputService.PreferredInput == Enum.PreferredInput.Touch then ICON_TOUCH else ICON_KEYBOARD
end

-- The action and name plates are drawn as a Shadow/face pair of labels; both carry the same text.
local function writePair(holder: Instance?, text: string): ()
	if not holder then
		return
	end

	for _, child in holder:GetChildren() do
		if child:IsA("TextLabel") then
			child.Text = text
		end
	end
end

-- Finds an authored target relative to any ancestor of the runtime prop. Door prompts use the
-- actual entrance model so perspective cannot pull the plate away from the visible doorway.
local function promptTargetPosition(part: BasePart, path: { string }): Vector3?
	local root = part.Parent
	while root and root ~= workspace do
		local target: Instance? = root
		for _, name in path do
			target = if target then target:FindFirstChild(name) else nil
			if not target then
				break
			end
		end

		if target then
			if target:IsA("BasePart") then
				return target.Position
			end
			if target:IsA("Model") then
				local frame = WorldPose.Bounds(target)
				return frame.Position
			end
		end

		root = root.Parent
	end

	return nil
end

--[[ Handling ]]--
function PromptHandler.OnInit(self: PromptHandler): ()
	self.Janitor = Janitor.new()
	self.Lifetime = Janitor.new()
	self.Lifetime:Add(self.Janitor, "Destroy")
	self.Current = nil
	self.HiddenAt = -math.huge
	self.ScreenOffset = Vector2.zero
	self.Highlight = InteractionHighlight.new(function(part: BasePart): BasePart
		return AmbientMotion:GetVisiblePart(part)
	end)
	self.Lifetime:Add(self.Highlight, "Destroy")
end

function PromptHandler.OnStart(self: PromptHandler): ()
	local assets = ReplicatedStorage:WaitForChild("Assets", TEMPLATE_TIMEOUT)
	local template = assets and assets:WaitForChild("Prompt", TEMPLATE_TIMEOUT)

	if not template or not template:IsA("BillboardGui") then
		print("[PromptHandler] Assets.Prompt is missing; falling back to the stock prompt UI")
		-- Server prompts are born Custom and would be invisible without the art, so each one that
		-- shows is flipped back to the stock look locally.
		self.Lifetime:Add(
			ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
				prompt.Style = Enum.ProximityPromptStyle.Default
			end),
			"Disconnect"
		)
		return
	end

	local billboard = template:Clone()
	billboard.Name = "PromptView"
	billboard.Enabled = false
	billboard.Active = true
	billboard.ResetOnSpawn = false
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Lifetime:Add(billboard, "Destroy")

	self.Billboard = billboard
	self.Root = billboard:FindFirstChild("Interact") :: Frame?
	self.Lifetime:Add(
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function(): ()
			if self.Current then
				self:Refresh(self.Current)
			end
		end),
		"Disconnect"
	)
	local scope = Scope.Run(function(): ()
		Flux(function(): ()
			-- Always subscribe, including boot when there is no current prompt yet.
			local page = Pages.Current()
			billboard.Enabled = self.Current ~= nil and page == Pages.Names.None
			self.Highlight:SetEnabled(billboard.Enabled and canHighlight(self.Current))
		end, true)
	end)
	self.Lifetime:Add(scope, "Destroy")

	self.Lifetime:Add(
		ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
			self:Show(prompt)
		end),
		"Disconnect"
	)

	self.Lifetime:Add(
		ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
			self:Hide(prompt)
		end),
		"Disconnect"
	)

	-- The local press is acknowledged on the spot; the action itself still waits for the server.
	self.Lifetime:Add(
		ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
			if player == Players.LocalPlayer and prompt == self.Current then
				self:Pressed(prompt)
			end
		end),
		"Disconnect"
	)

	-- A Custom-style prompt has no stock button, so the plate itself answers a tap or a click --
	-- that is what the cursor icon in the art promises. The keyboard key keeps working on its own.
	local root = self.Root
	if root then
		self.Lifetime:Add(bindLayout(billboard, root), "Destroy")
		-- The plate still answers a mouse click while inactive; only touch and gamepad need it to sink input.
		self.Lifetime:Add(Press.SinkUnlessMouse(root), "Destroy")

		self.Lifetime:Add(
			root.InputBegan:Connect(function(input: InputObject)
				if self.Current and billboard.Enabled and PRESS_INPUTS[input.UserInputType] then
					self.Current:InputHoldBegin()
				end
			end),
			"Disconnect"
		)

		self.Lifetime:Add(
			root.InputEnded:Connect(function(input: InputObject)
				if self.Current and PRESS_INPUTS[input.UserInputType] then
					self.Current:InputHoldEnd()
				end
			end),
			"Disconnect"
		)
	end
end

--- Adorns the billboard to the prompt's part and rides it in. Prompts that kept the stock style
--- (none today) are left to the engine.
function PromptHandler.Show(self: PromptHandler, prompt: ProximityPrompt): ()
	local billboard = self.Billboard
	if not billboard or prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return
	end

	local part = prompt.Parent
	if not part or not part:IsA("BasePart") then
		return
	end

	-- Still showing another prompt, or it only just left: the plate moves over instead of
	-- leaving and entering again.
	local swapping = self.Current ~= nil or os.clock() - self.HiddenAt < SWAP_SECONDS
	self.Current = prompt
	self.Janitor:Cleanup()

	billboard.Adornee = part
	local kindName = part:GetAttribute(BuildingsConfig.KindAttribute)
	local kind = if typeof(kindName) == "string" then BuildingsConfig.Kinds[kindName] else nil
	self.ScreenOffset = if kind and kind.PromptScreenOffset then kind.PromptScreenOffset else Vector2.zero
	local targetPosition = if kind and kind.PromptTarget then promptTargetPosition(part, kind.PromptTarget) else nil
	if targetPosition then
		billboard.StudsOffset = Vector3.zero
		billboard.StudsOffsetWorldSpace = targetPosition - part.Position
	else
		local lift = if kind and kind.PromptLift ~= nil then kind.PromptLift else part.Size.Y / 2 + PROMPT_LIFT
		billboard.StudsOffset = Vector3.new(0, lift, 0)
		billboard.StudsOffsetWorldSpace = Vector3.zero
	end

	self:Refresh(prompt)
	self.Highlight:Show(part)

	-- InteractHandler rewrites both texts on its refresh tick, so the plate follows them live --
	-- ObjectText carries the status line with the countdowns.
	self.Janitor:Add(
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			self:Refresh(prompt)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			self:Refresh(prompt)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function(): ()
			if not prompt.Enabled then
				self:Hide(prompt)
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		prompt.AncestryChanged:Connect(function(): ()
			if not prompt:IsDescendantOf(workspace) then
				self:Hide(prompt)
			end
		end),
		"Disconnect"
	)

	billboard.Enabled = Pages.Current:peek() == Pages.Names.None
	self.Highlight:SetEnabled(billboard.Enabled and canHighlight(prompt))

	local root = self.Root
	if root and swapping then
		Animate.Settle(root)
		Animate.Pop(root, SWAP_POP)
	elseif root then
		Animate.Enter(root)
	end
end

function PromptHandler.Pressed(self: PromptHandler, prompt: ProximityPrompt): ()
	local part = prompt.Parent
	local root = self.Root
	if not root or not part or not part:IsA("BasePart") or not part:HasTag(BuildingsConfig.Tag) then
		return
	end
	-- A status-only plate has nothing to press.
	if Interact:Describe(part).Fire == nil then
		return
	end
	Animate.Pop(root, PRESS_POP)
end

function PromptHandler.Hide(self: PromptHandler, prompt: ProximityPrompt): ()
	local billboard = self.Billboard
	if not billboard or self.Current ~= prompt then
		return
	end

	self.Current = nil
	self.HiddenAt = os.clock()
	self.Janitor:Cleanup()
	self.Highlight:Hide()

	local root = self.Root
	if not root then
		billboard.Enabled = false
		return
	end

	Animate.ExitThen(root, function()
		-- A newer prompt may have taken the billboard while the exit spring ran.
		if not self.Current then
			billboard.Enabled = false
		end
	end)
end

function PromptHandler.Refresh(self: PromptHandler, prompt: ProximityPrompt): ()
	self.Highlight:SetEnabled(Pages.Current:peek() == Pages.Names.None and canHighlight(prompt))
	local billboard = self.Billboard
	if billboard then
		-- The desktop doorway offset pushes the plate outside a narrow phone screen.
		billboard.SizeOffset = if UserInputService.PreferredInput == Enum.PreferredInput.Touch
			then Vector2.zero
			else self.ScreenOffset
	end
	local root = self.Root
	if not root then
		return
	end

	writePair(root:FindFirstChild("Txt"), prompt.ActionText)
	writePair(root:FindFirstChild("Name"), prompt.ObjectText)

	-- A status-only prompt (a busy station) keeps just its name plate: no action, no key icon.
	local actionable = prompt.ActionText ~= ""
	local action = root:FindFirstChild("Txt")
	if action and action:IsA("GuiObject") then
		action.Visible = actionable
	end
	self:StatusLayout(root, not actionable, prompt:GetAttribute(StationStatusConfig.AlertAttribute) == true)

	-- The art stacks one icon per input kind (plus spare variants); exactly one is up.
	local chosen = pickIcon()
	local shown = not actionable

	for _, child in root:GetChildren() do
		if child:IsA("ImageLabel") and string.sub(child.Name, 1, 4) == "Icon" then
			local wanted = child.Name == chosen and not shown
			if wanted and chosen == ICON_GAMEPAD then
				child.Image = UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
				child.ImageColor3 = Color3.fromRGB(95, 49, 30)
			end
			child.Visible = wanted
			shown = shown or wanted
		end
	end
end

type Authored = {
	Position: UDim2,
	NameSize: UDim2,
	-- The card art (background, dashed lines) a status line floats without.
	Card: { [GuiObject]: boolean },
	CardStrokes: { [UIStroke]: boolean },
	-- The wooden sign drawn behind the status line instead.
	Plate: ImageLabel,
	-- Each name label's own position, colour, alignment, visibility and authored outline state.
	Labels: { [TextLabel]: { Position: UDim2, Color: Color3, Alignment: Enum.TextXAlignment, Visible: boolean } },
	Strokes: { [UIStroke]: boolean },
}

local function remember(root: Frame, name: GuiObject): Authored
	local labels = {}
	local strokes = {}
	for _, child in name:GetDescendants() do
		if child:IsA("TextLabel") then
			labels[child] = {
				Position = child.Position,
				Color = child.TextColor3,
				Alignment = child.TextXAlignment,
				Visible = child.Visible,
			}
		elseif child:IsA("UIStroke") then
			strokes[child] = child.Enabled
		end
	end
	local card = {}
	local cardStrokes = {}
	for _, piece in { root:FindFirstChild("Bg"), root:FindFirstChild("InnerLines") } do
		if piece and piece:IsA("GuiObject") then
			card[piece] = piece.Visible
			for _, child in piece:GetDescendants() do
				if child:IsA("UIStroke") then
					cardStrokes[child] = child.Enabled
				end
			end
		end
	end
	local plate = Instance.new("ImageLabel")
	plate.Name = "StatusPlate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = PromptConfig.StatusPlateSize
	plate.BackgroundTransparency = 1
	plate.Image = STATUS_PLATE_IMAGE
	plate.ScaleType = Enum.ScaleType.Stretch
	plate.ZIndex = math.max(name.ZIndex - 1, 1)
	plate.Visible = false
	plate.Parent = root
	return {
		Plate = plate,
		Position = name.Position,
		NameSize = name.Size,
		Card = card,
		CardStrokes = cardStrokes,
		Labels = labels,
		Strokes = strokes,
	}
end

-- Remembers the authored name plate, then switches between it and the status line: the card art
-- gives way to the wooden sign, with white lettering over a short drop shadow. An alert line asks the
-- player to act and is drawn as StationStatusHandler's firebox icon instead, so the plate shows nothing.
function PromptHandler.StatusLayout(self: PromptHandler, root: Frame, status: boolean, alerted: boolean): ()
	local billboard = self.Billboard
	local name = root:FindFirstChild("Name")
	if not billboard or not name or not name:IsA("GuiObject") then
		return
	end
	local authored = self.Authored or remember(root, name)
	self.Authored = authored
	name.Position = if status then STATUS_NAME_POSITION else authored.Position
	name.Size = if status then PromptConfig.StatusNameSize else authored.NameSize
	billboard:SetAttribute("StatusOnly", status)
	for piece, visible in authored.Card do
		piece.Visible = visible and not status
	end
	-- Disable the card border explicitly; only the wooden image frames a status line.
	for stroke, enabled in authored.CardStrokes do
		stroke.Enabled = enabled and not status
	end
	local alert = status and alerted
	authored.Plate.Visible = status and not alert
	for label, original in authored.Labels do
		-- The pair's dark half drops below the face and becomes its shadow.
		local shadow = label.Name == "Shadow"
		label.Visible = original.Visible and not alert
		label.Position = if status and shadow then original.Position + STATUS_SHADOW_DROP else original.Position
		label.TextColor3 = if not status then original.Color elseif shadow then STATUS_INK else STATUS_FACE
		-- The authored name sits left beside the input icon; a status line centres on the sign.
		label.TextXAlignment = if status then Enum.TextXAlignment.Center else original.Alignment
	end
	-- Authored strokes use ScaledSize; preserve their tuning and omit them from status text.
	for stroke, enabled in authored.Strokes do
		stroke.Enabled = enabled and not status
	end
end

function PromptHandler.Destroy(self: PromptHandler): ()
	self.Current = nil
	self.Lifetime:Destroy()
end

function PromptHandler.GetActiveView(self: PromptHandler): (ProximityPrompt?, BillboardGui?, Frame?)
	return self.Current, self.Billboard, self.Root
end

export type PromptHandler = typeof(PromptHandler) & {
	Janitor: any,
	Lifetime: any,
	Billboard: BillboardGui?,
	Root: Frame?,
	Current: ProximityPrompt?,
	-- When the plate last lost its prompt; see SWAP_SECONDS.
	HiddenAt: number,
	-- The authored billboard size and name plate, restored when a status card turns actionable.
	Authored: Authored?,
	ScreenOffset: Vector2,
	Highlight: InteractionHighlight.InteractionHighlight,
}

return PromptHandler :: PromptHandler
