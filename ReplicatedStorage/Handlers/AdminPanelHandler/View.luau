--!strict
-- Owned, responsive developer UI. No place-authored screen is replaced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Admin)

local BACKGROUND = Color3.fromRGB(23, 27, 36)
local SURFACE = Color3.fromRGB(38, 44, 57)
local TEXT = Color3.fromRGB(239, 242, 248)
local ACCENT = Color3.fromRGB(71, 117, 101)
local DANGER = Color3.fromRGB(129, 52, 62)

local View = {}

local function corner(parent: GuiObject): ()
	local rounding = Instance.new("UICorner")
	rounding.CornerRadius = UDim.new(0, 9)
	rounding.Parent = parent
end

local function label(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextLabel
	local node = Instance.new("TextLabel")
	node.Name = name
	node.BackgroundTransparency = 1
	node.Text = text
	node.TextColor3 = TEXT
	node.Font = Enum.Font.Gotham
	node.TextSize = 15
	node.TextXAlignment = Enum.TextXAlignment.Left
	node.TextYAlignment = Enum.TextYAlignment.Top
	node.TextWrapped = true
	node.Position = position
	node.Size = size
	node.Parent = parent
	return node
end

local function button(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextButton
	local node = Instance.new("TextButton")
	node.Name = name
	node.Text = text
	node.TextColor3 = TEXT
	node.BackgroundColor3 = SURFACE
	node.BorderSizePixel = 0
	node.Font = Enum.Font.GothamMedium
	node.TextSize = 14
	node.TextWrapped = true
	node.Position = position
	node.Size = size
	node.Parent = parent
	corner(node)
	return node
end

local function scroll(parent: Instance, name: string, position: UDim2, size: UDim2): ScrollingFrame
	local node = Instance.new("ScrollingFrame")
	node.Name = name
	node.Position = position
	node.Size = size
	node.BackgroundTransparency = 1
	node.BorderSizePixel = 0
	node.ScrollBarThickness = 4
	node.ScrollBarImageColor3 = Color3.fromRGB(140, 158, 177)
	node.CanvasSize = UDim2.new()
	node.AutomaticCanvasSize = Enum.AutomaticSize.Y
	node.ScrollingDirection = Enum.ScrollingDirection.Y
	node.Parent = parent
	return node
end

function View.Create(playerGui: PlayerGui, owner: any): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "AdminPanel"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = Config.DisplayOrder
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	owner:Add(screen)
	local toggle = button(screen, "Toggle", "ADMIN • F4", UDim2.new(1, -136, 0, 8), UDim2.fromOffset(124, 36))
	toggle.BackgroundColor3 = ACCENT
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(700, 650)
	panel.BackgroundColor3 = BACKGROUND
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.Parent = screen
	corner(panel)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local bounds = Instance.new("Frame")
	bounds.Name = "ViewportBounds"
	bounds.Size = UDim2.fromScale(1, 1)
	bounds.BackgroundTransparency = 1
	bounds.Visible = false
	bounds.Parent = screen
	local function resize(): ()
		local size = bounds.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		-- Short displays shrink the ordinary action list before scaling the fixed controls.
		local height = math.clamp(size.Y - 16, 540, 650)
		scale.Scale = math.min(1, math.max(1, size.Y - 16) / height, math.max(1, size.X - 16) / 300)
		local width = math.min(700, math.max(1, size.X - 16) / scale.Scale)
		panel.Size = UDim2.fromOffset(width, height)
	end
	owner:Add(bounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	resize()
	label(panel, "Title", "DEVELOPER PANEL", UDim2.fromOffset(18, 18), UDim2.new(1, -80, 0, 24)).Font =
		Enum.Font.GothamBold
	label(
		panel,
		"Subtitle",
		if playerGui.Parent and playerGui.Parent:GetAttribute("AdminPanelMockData") == true
			then "STUDIO MOCK • test data"
			else "Current server only • changes are saved",
		UDim2.fromOffset(18, 45),
		UDim2.new(1, -36, 0, 34)
	).TextSize =
		12
	local close = button(panel, "Close", "×", UDim2.new(1, -48, 0, 12), UDim2.fromOffset(34, 32))
	local previous = button(panel, "Previous", "‹", UDim2.fromOffset(18, 80), UDim2.fromOffset(36, 42))
	local nextButton = button(panel, "Next", "›", UDim2.new(1, -54, 0, 80), UDim2.fromOffset(36, 42))
	local target = label(panel, "Target", "", UDim2.fromOffset(64, 80), UDim2.new(1, -128, 0, 42))
	target.TextYAlignment = Enum.TextYAlignment.Center
	target.TextSize = 14
	label(panel, "AmountLabel", "Amount", UDim2.fromOffset(18, 138), UDim2.fromOffset(112, 22))
	local amount = Instance.new("TextBox")
	amount.Name = "Amount"
	amount.Position = UDim2.fromOffset(130, 130)
	amount.Size = UDim2.new(1, -148, 0, 38)
	amount.BackgroundColor3 = SURFACE
	amount.TextColor3 = TEXT
	amount.Font = Enum.Font.Gotham
	amount.TextSize = 16
	amount.Text = "1000"
	amount.PlaceholderText = "Whole number"
	amount.ClearTextOnFocus = false
	amount.Parent = panel
	corner(amount)
	local danger = Instance.new("Frame")
	danger.Name = "DangerZone"
	danger.Position = UDim2.fromOffset(18, 184)
	danger.Size = UDim2.new(1, -36, 0, 80)
	danger.BackgroundColor3 = Color3.fromRGB(47, 31, 38)
	danger.BorderSizePixel = 0
	danger.Parent = panel
	corner(danger)
	local reset = Config.ById.resetProgress
	local dangerTitle = label(danger, "Title", reset.section, UDim2.fromOffset(12, 10), UDim2.new(0.5, -18, 0, 18))
	dangerTitle.Font = Enum.Font.GothamBold
	dangerTitle.TextSize = 14
	dangerTitle.TextColor3 = Color3.fromRGB(255, 184, 190)
	label(
		danger,
		"Warning",
		"Deletes progress.\nRequires rejoin.",
		UDim2.fromOffset(12, 32),
		UDim2.new(0.5, -18, 0, 38)
	).TextSize =
		12
	local resetButton = button(danger, reset.id, reset.label, UDim2.new(0.5, 6, 0, 16), UDim2.new(0.5, -18, 0, 48))
	resetButton.BackgroundColor3 = DANGER
	local actions = scroll(panel, "Actions", UDim2.fromOffset(18, 276), UDim2.new(1, -36, 1, -468))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 62)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = actions
	local buttons: { [string]: TextButton } = { [reset.id] = resetButton }
	for index, definition in Config.Actions do
		if definition.id == reset.id then
			continue
		end
		local text = `{definition.section}\n{definition.label}`
		if definition.max then
			text ..= ` (≤ {definition.max})`
		end
		local actionButton = button(actions, definition.id, text, UDim2.new(), UDim2.new())
		actionButton.LayoutOrder = index
		buttons[definition.id] = actionButton
	end
	local confirm = Instance.new("Frame")
	confirm.Name = "Confirmation"
	confirm.Position = danger.Position
	confirm.Size = UDim2.new(1, -36, 1, -376)
	confirm.BackgroundColor3 = SURFACE
	confirm.BorderSizePixel = 0
	confirm.Visible = false
	confirm.Parent = panel
	corner(confirm)
	local confirmScroll = scroll(confirm, "Details", UDim2.fromOffset(14, 12), UDim2.new(1, -28, 1, -76))
	local confirmText = label(confirmScroll, "Text", "", UDim2.new(), UDim2.new(1, -8, 0, 0))
	confirmText.AutomaticSize = Enum.AutomaticSize.Y
	local accept = button(confirm, "Accept", "CONFIRM", UDim2.new(0, 12, 1, -52), UDim2.new(0.5, -18, 0, 40))
	accept.BackgroundColor3 = DANGER
	local cancel = button(confirm, "Cancel", "Cancel", UDim2.new(0.5, 6, 1, -52), UDim2.new(0.5, -18, 0, 40))
	buttons.inspect = button(panel, "Inspect", "Refresh status", UDim2.new(0, 18, 1, -180), UDim2.new(0.5, -22, 0, 34))
	buttons.audit = button(panel, "Audit", "Server log", UDim2.new(0.5, 4, 1, -180), UDim2.new(0.5, -22, 0, 34))
	local resultScroll = scroll(panel, "ResultScroll", UDim2.new(0, 18, 1, -134), UDim2.new(1, -36, 0, 116))
	local result = label(resultScroll, "Result", "Select a player and an action.", UDim2.new(), UDim2.new(1, -8, 0, 0))
	result.TextSize = 13
	result.AutomaticSize = Enum.AutomaticSize.Y
	return {
		Panel = panel,
		Toggle = toggle,
		Close = close,
		Target = target,
		Previous = previous,
		Next = nextButton,
		Amount = amount,
		Danger = danger,
		Actions = actions,
		Buttons = buttons,
		Confirm = confirm,
		ConfirmText = confirmText,
		ConfirmScroll = confirmScroll,
		Accept = accept,
		Cancel = cancel,
		Result = result,
		ResultScroll = resultScroll,
	}
end

export type View = {
	Panel: Frame,
	Toggle: TextButton,
	Close: TextButton,
	Target: TextLabel,
	Previous: TextButton,
	Next: TextButton,
	Amount: TextBox,
	Danger: Frame,
	Actions: ScrollingFrame,
	Buttons: { [string]: TextButton },
	Confirm: Frame,
	ConfirmText: TextLabel,
	ConfirmScroll: ScrollingFrame,
	Accept: TextButton,
	Cancel: TextButton,
	Result: TextLabel,
	ResultScroll: ScrollingFrame,
}

return View
