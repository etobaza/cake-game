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
local Scope = require(_Shared.UI.Scope)

--[[ Constants ]]--
local TEMPLATE_TIMEOUT = 10
-- Studs above the top of the adorned part, matching where the artist floated the sample.
local PROMPT_LIFT = 1
-- Keep a readable, tappable plate on phones without covering the station/player.
local PHONE_SCALE = 0.7
local PHONE_WIDTH = 700
local PHONE_HEIGHT = 500
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

--[[ Tables ]]--
local PromptHandler = {
	-- Resolve visible garden copies and query the existing interaction policy after their owners initialize.
	dependencies = { "AmbientMotionHandler", "InteractHandler" },
}

--[[ Private Functions ]]--
local function bindLayout(root: Frame): any
	local janitor = Janitor.new()
	local cameraJanitor = Janitor.new()
	janitor:Add(cameraJanitor, "Destroy")
	janitor:Add(Animate.Scale(root), "destroy")
	-- Center the scaled art on its billboard; enter/exit motion keeps the same rest point.
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	Animate.Place(root, UDim2.fromScale(0.5, 0.5))
	local function update(): ()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.zero
		local phone = UserInputService.TouchEnabled
			and viewport.X > 0
			and viewport.Y > 0
			and (viewport.X < PHONE_WIDTH or viewport.Y < PHONE_HEIGHT)
		Animate.SetLayoutScale(root, if phone then PHONE_SCALE else 1)
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
	janitor:Add(UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(update), "Disconnect")
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
				local frame = target:GetBoundingBox()
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
		warn("[PromptHandler] Assets.Prompt is missing; falling back to the stock prompt UI")
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

	-- A Custom-style prompt has no stock button, so the plate itself answers a tap or a click --
	-- that is what the cursor icon in the art promises. The keyboard key keeps working on its own.
	local root = self.Root
	if root then
		self.Lifetime:Add(bindLayout(root), "Destroy")
		root.Active = true

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
	if root then
		Animate.Enter(root)
	end
end

function PromptHandler.Hide(self: PromptHandler, prompt: ProximityPrompt): ()
	local billboard = self.Billboard
	if not billboard or self.Current ~= prompt then
		return
	end

	self.Current = nil
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

	-- The art stacks one icon per input kind (plus spare variants); exactly one is up.
	local chosen = pickIcon()
	local shown = false

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
	ScreenOffset: Vector2,
	Highlight: InteractionHighlight.InteractionHighlight,
}

return PromptHandler :: PromptHandler
