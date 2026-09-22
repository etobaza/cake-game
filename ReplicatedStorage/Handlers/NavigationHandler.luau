--!strict
-- Gamepad page focus and back navigation. Pages remains the owner of modal state;
-- Roblox handles directional selection and scrolls selected descendants into view.

--[[ Services ]]--
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Constants ]]--
local MENU_ACTION = "CakeMenu"
local BACK_ACTION = "CakeBack"
local WORLD_ACTION = "CakeModalInteraction"

--[[ Tables ]]--
local NavigationHandler = {
	-- Screen references exist only after the UI has mounted.
	dependencies = { "UIHandler" },
}

--[[ Private Functions ]]--
local function visible(object: GuiObject, root: Instance): boolean
	if not object:IsDescendantOf(root) or not object.Selectable or not object.Interactable then
		return false
	end
	local current: Instance? = object
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
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
	local scope = Scope.Run(function(): ()
		Flux(function(): ()
			local page = Pages.Current()
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
		Enum.KeyCode.ButtonY
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
		Enum.KeyCode.ButtonB
	)
	ContextActionService:BindActionAtPriority(WORLD_ACTION, function(): Enum.ContextActionResult
		return if Pages.Current:peek() ~= Pages.Names.None or GuiService.SelectedObject ~= nil
			then Enum.ContextActionResult.Sink
			else Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonX)
	self.Janitor:Add(function(): ()
		for _, action in { MENU_ACTION, BACK_ACTION, WORLD_ACTION } do
			ContextActionService:UnbindAction(action)
		end
		GuiService.SelectedObject = nil
	end)
	self:Refresh()
end

function NavigationHandler.Refresh(self: NavigationHandler): ()
	if GuiService.MenuIsOpen then
		return
	end
	local gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
	local hint = UIHandler:GetHud("Controls.GamepadHint") :: TextLabel
	local menuKey = string.gsub(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonY), "^Button", "")
	local interactKey = string.gsub(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonX), "^Button", "")
	hint.Text = `{menuKey}: Menu   {interactKey}: Interact   L3: Run`
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
		local shop = UIHandler:GetHud("SideBtns.Shop.Btn") :: GuiObject
		if visible(shop, root) and inView(shop) then
			GuiService.SelectedObject = shop
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

function NavigationHandler.WatchSelection(self: NavigationHandler): ()
	self.Selection:Cleanup()
	local selected = GuiService.SelectedObject
	if not selected then
		return
	end
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
	Browsing: boolean,
}

return NavigationHandler :: NavigationHandler
