--!strict
-- Gamepad page focus and back navigation. Pages remains the owner of modal state;
-- Roblox handles directional selection and scrolls selected descendants into view. Also draws the
-- themed focus ring and the HUD's controller glyph row.

--[[ Services ]]--
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Flux = require(ReplicatedStorage.Packages.flux)
local InputCue = require(ReplicatedStorage.Shared.UI.InputCue)
local InputCues = require(ReplicatedStorage.Shared.Configs.InputCues)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Constants ]]--
local MENU_ACTION = "CakeMenu"
local BACK_ACTION = "CakeBack"
local WORLD_ACTION = "CakeModalInteraction"
-- First HUD focus: Upgrades is where the loop leads, not the Robux shop. The tutorial hides it, so
-- the next visible side button takes over.
local HUD_FOCUS = { "SideBtns.Upgrades.Btn", "SideBtns.Shop.Btn", "SideBtns.Rewards" }

--[[ Tables ]]--
local NavigationHandler = {
	-- Screen references exist only after the UI has mounted.
	dependencies = { "UIHandler" },
}

--[[ Private Functions ]]--
-- Checked up to PlayerGui, not just to root: a disabled screen above root hides it too.
local function visible(object: GuiObject, root: Instance): boolean
	return object:IsDescendantOf(root) and object.Selectable and object.Interactable and InputCue.OnScreen(object)
end

local function inView(object: GuiObject): boolean
	local point = object.AbsolutePosition + object.AbsoluteSize / 2
	local current: Instance? = object.Parent
	while current do
		if current:IsA("GuiObject") and current.ClipsDescendants then
			local position, size = current.AbsolutePosition, current.AbsoluteSize
			if
				point.X < position.X
				or point.Y < position.Y
				or point.X > position.X + size.X
				or point.Y > position.Y + size.Y
			then
				return false
			end
		end
		current = current.Parent
	end
	local camera = workspace.CurrentCamera
	return camera ~= nil
		and point.X >= 0
		and point.Y >= 0
		and point.X < camera.ViewportSize.X
		and point.Y < camera.ViewportSize.Y
end

--[[ Handling ]]--
function NavigationHandler.OnInit(self: NavigationHandler): ()
	self.Janitor = Janitor.new()
	self.Selection = Janitor.new()
	self.Janitor:Add(self.Selection, "Destroy")
	self.Browsing = false
end

function NavigationHandler.OnStart(self: NavigationHandler): ()
	local function refresh(): ()
		self:Refresh()
	end
	local tutorial = UIHandler:GetPanel("Tutorial")
	if tutorial then
		self.Janitor:Add(
			tutorial:GetAttributeChangedSignal("HelpOpen"):Connect(function(): ()
				if tutorial:GetAttribute("HelpOpen") then
					self.Browsing = true
				end
				self:Refresh()
			end),
			"Disconnect"
		)
	end
	self.Janitor:Add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh), "Disconnect")
	self.Janitor:Add(
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function(): ()
			self:WatchSelection()
		end),
		"Disconnect"
	)
	self.Janitor:Add(GuiService.MenuClosed:Connect(refresh), "Disconnect")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local ring = InputCue.SelectionRing()
	self.Janitor:Add(ring, "Destroy")
	self.Ring = ring
	playerGui.SelectionImageObject = ring
	local scope = Scope.Run(function(): ()
		Flux(function(): ()
			local page = Pages.Current()
			Pages.TrackPresenting()
			self.Browsing = page ~= Pages.Names.None
			task.defer(refresh)
		end, true)
	end)
	self.Janitor:Add(scope, "Destroy")
	ContextActionService:BindAction(
		MENU_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if GuiService.MenuIsOpen then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				self.Browsing = not self.Browsing or Pages.Current:peek() ~= Pages.Names.None
				self:Refresh()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		InputCues.Hints.Keys.Menu
	)
	ContextActionService:BindAction(
		BACK_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			if not self.Browsing and not GuiService.SelectedObject and Pages.Current:peek() == Pages.Names.None then
				return Enum.ContextActionResult.Pass
			end
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			if tutorial and tutorial:GetAttribute("HelpOpen") then
				tutorial:SetAttribute("HelpOpen", false)
				self.Browsing = false
				self:Refresh()
				return Enum.ContextActionResult.Sink
			end
			local closed = if Pages.Current:peek() ~= Pages.Names.None then Pages.Close() else true
			if closed then
				self.Browsing = false
			end
			self:Refresh()
			return Enum.ContextActionResult.Sink
		end,
		false,
		InputCues.Keys.Close
	)
	ContextActionService:BindActionAtPriority(WORLD_ACTION, function(): Enum.ContextActionResult
		return if Pages.Current:peek() ~= Pages.Names.None or GuiService.SelectedObject ~= nil
			then Enum.ContextActionResult.Sink
			else Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, InputCues.Hints.Keys.Interact)
	self.Janitor:Add(function(): ()
		for _, action in { MENU_ACTION, BACK_ACTION, WORLD_ACTION } do
			ContextActionService:UnbindAction(action)
		end
		GuiService.SelectedObject = nil
		-- The engine type omits nil, which restores the default ring.
		playerGui.SelectionImageObject = nil :: any
	end)
	self:BindHints()
	self:Refresh()
end

function NavigationHandler.Refresh(self: NavigationHandler): ()
	if GuiService.MenuIsOpen or Pages.Presenting:peek() then
		return
	end
	local gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
	local hint = UIHandler:GetHud("Controls.GamepadHint") :: GuiObject
	hint.Visible = gamepad and Pages.Current:peek() == Pages.Names.None
	if not gamepad or not self.Browsing then
		GuiService.SelectedObject = nil
		return
	end
	local page = Pages.Current:peek()
	local root: Instance? = if page == Pages.Names.None
		then UIHandler:GetHud("Controls").Parent
		else UIHandler:GetPanel(page)
	local tutorial = UIHandler:GetPanel("Tutorial")
	local helpOpen = tutorial ~= nil and tutorial:GetAttribute("HelpOpen") == true
	if tutorial and helpOpen then
		root = tutorial:FindFirstChild("Help")
	end
	if not root then
		return
	end
	if root:IsA("ScreenGui") and not root.Enabled then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and visible(selected, root) then
		return
	end
	GuiService.SelectedObject = nil
	if page == Pages.Names.None and not helpOpen then
		local help = tutorial and tutorial:FindFirstChild("HelpButton")
		if tutorial and help and help:IsA("GuiObject") and visible(help, tutorial) then
			GuiService.SelectedObject = help
			return
		end
		for _, path in HUD_FOCUS do
			local button = UIHandler:GetHud(path) :: GuiObject
			if visible(button, root) and inView(button) then
				GuiService.SelectedObject = button
				return
			end
		end
		return
	end
	-- GUI layout/enter springs may still be settling when the page signal fires.
	local target: GuiObject? = nil
	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("GuiObject") or not visible(descendant, root) then
			continue
		end
		if not descendant.Active or descendant.AbsoluteSize.X <= 0 or not inView(descendant) then
			continue
		end
		if
			not target
			or descendant.SelectionOrder < target.SelectionOrder
			or (
				descendant.SelectionOrder == target.SelectionOrder
				and descendant.AbsolutePosition.Y < target.AbsolutePosition.Y
			)
		then
			target = descendant
		end
	end
	GuiService.SelectedObject = target
end

-- Fills each authored hint entry's badge with the connected controller's glyph.
function NavigationHandler.BindHints(self: NavigationHandler): ()
	local hint = UIHandler:GetHud("Controls.GamepadHint")
	local function render(): ()
		for name, key in InputCues.Hints.Keys :: { [string]: Enum.KeyCode } do
			local entry = hint:FindFirstChild(name)
			local badge = entry and entry:FindFirstChild("Badge")
			local glyph = badge and badge:FindFirstChild("Glyph")
			if badge and badge:IsA("Frame") and glyph and glyph:IsA("ImageLabel") then
				InputCue.Render(badge, key, InputCues.Hints.BadgeSize)
			else
				print(`[NavigationHandler] the gamepad hint has no '{name}.Badge.Glyph'`)
			end
		end
	end
	render()
	self.Janitor:Add(UserInputService.GamepadConnected:Connect(render), "Disconnect")
end

function NavigationHandler.WatchSelection(self: NavigationHandler): ()
	self.Selection:Cleanup()
	local selected = GuiService.SelectedObject
	if not selected then
		return
	end
	InputCue.FitRing(self.Ring, selected)
	local function refresh(): ()
		task.defer(function(): ()
			self:Refresh()
		end)
	end
	self.Selection:Add(selected.AncestryChanged:Connect(refresh), "Disconnect")
	self.Selection:Add(selected:GetPropertyChangedSignal("Selectable"):Connect(refresh), "Disconnect")
	local current: Instance? = selected
	while current and not current:IsA("PlayerGui") do
		if current:IsA("GuiObject") then
			self.Selection:Add(current:GetPropertyChangedSignal("Visible"):Connect(refresh), "Disconnect")
		end
		current = current.Parent
	end
end

function NavigationHandler.Destroy(self: NavigationHandler): ()
	self.Janitor:Destroy()
end

export type NavigationHandler = typeof(NavigationHandler) & {
	Janitor: any,
	Selection: any,
	Ring: Frame,
	Browsing: boolean,
}

return NavigationHandler :: NavigationHandler
