--!strict
-- Stable authored hitboxes contain centered artwork wrappers. Only their artwork grows and lights up.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]
--
local Config = require(ReplicatedStorage.Shared.Configs.ButtonRow)
local HoverRoom = require(script.Parent.HoverRoom)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Press = require(script.Parent.Press)
local Ripple = require(ReplicatedStorage.Shared.Libs.Ripple)

--[[ Constants ]]
--
local CENTER = Vector2.new(0.5, 0.5)

--[[ Types ]]
--
type Entry = {
	Button: GuiObject,
	Scaler: UIScale,
	Motion: Ripple.Motion<number>,
	Glow: Ripple.Motion<number>,
	Highlight: GuiObject?,
	-- The room last measured while focused; it stays while the artwork shrinks back.
	Limit: number,
	Pressed: InputObject?,
}

--[[ Tables ]]
--
local ButtonRow = {}

--[[ Private Functions ]]
--
local function available(button: GuiObject): boolean
	if not button.Interactable or not button:IsDescendantOf(game) then
		return false
	end

	local ancestor: Instance? = button
	while ancestor do
		if ancestor:IsA("GuiObject") and not ancestor.Visible then
			return false
		end
		if ancestor:IsA("LayerCollector") and not ancestor.Enabled then
			return false
		end
		ancestor = ancestor.Parent
	end
	return true
end

local function moveArtwork(source: GuiObject, target: GuiObject): ()
	for _, child in source:GetChildren() do
		if child:IsA("GuiObject") and child ~= target then
			child.Parent = target
		end
	end
end

-- The wash is a child of the background so it draws above the fill and below the caption.
local function createHighlight(wrapper: GuiObject): GuiObject?
	local background = wrapper:FindFirstChild("Bg")
	if not background or not background:IsA("GuiObject") then
		return nil
	end
	local style = Config.Highlight
	local inset = if background:IsA("ImageLabel") then style.ImageInset else 0
	local highlight = Instance.new("Frame")
	highlight.Name = "HoverHighlight"
	highlight.BackgroundColor3 = style.Color
	highlight.BackgroundTransparency = 1
	highlight.BorderSizePixel = 0
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.Position = UDim2.fromScale(0.5, 0.5)
	highlight.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	highlight.ZIndex = background.ZIndex
	highlight.Visible = false
	local authoredCorner = background:FindFirstChildOfClass("UICorner")
	local corner = if authoredCorner then authoredCorner:Clone() else Instance.new("UICorner")
	if not authoredCorner then
		corner.CornerRadius = style.ImageCorner
	end
	corner.Parent = highlight
	highlight.Parent = background
	return highlight
end

local function wrapArtwork(button: GuiObject, owner: Janitor.Janitor): Entry
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Wrap"
	wrapper.BackgroundTransparency = 1
	wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapper.Position = UDim2.fromScale(0.5, 0.5)
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.ZIndex = button.ZIndex
	wrapper.Parent = button
	moveArtwork(button, wrapper)

	local scaler = Instance.new("UIScale")
	scaler.Parent = wrapper
	local spring = { frequency = Config.Spring.frequency, dampingRatio = Config.Spring.dampingRatio }
	local motion = Ripple.createMotion(1, { start = true, spring = spring })
	local glow = Ripple.createMotion(0, { start = true, spring = spring })
	local highlight = createHighlight(wrapper)
	local entry: Entry = {
		Button = button,
		Scaler = scaler,
		Motion = motion,
		Glow = glow,
		Highlight = highlight,
		Limit = 1,
		Pressed = nil,
	}
	motion:onChange(function(value: number): ()
		-- Fast reversals must never push artwork past the room the row measured for it.
		scaler.Scale = math.clamp(value, 0, entry.Limit)
	end)
	if highlight then
		local fullTransparency = Config.Highlight.Transparency
		glow:onChange(function(value: number): ()
			local strength = math.clamp(value, 0, 1)
			highlight.Visible = strength > 0.01
			highlight.BackgroundTransparency = 1 - strength * (1 - fullTransparency)
		end)
	end
	local wasActive = button.Active
	button.Active = true
	owner:Add(function(): ()
		motion:destroy()
		glow:destroy()
		if highlight then
			highlight:Destroy()
		end
		if button.Parent then
			button.Active = wasActive
			moveArtwork(wrapper, button)
		end
		wrapper:Destroy()
	end, true)

	return entry
end

--[[ Handling ]]
--
-- The supplied controls are transparent authored containers; Bg/Txt/Icon carry their artwork.
-- Keep the controls in place so routing, layout, touch targets and selection remain stable.
function ButtonRow.Bind(row: GuiObject, buttons: { GuiObject }): Janitor.Janitor
	local owner = Janitor.new()
	local entries: { Entry } = {}
	local hovered: GuiObject? = nil
	local selected: GuiObject? = nil

	local function refresh(): ()
		for _, entry in entries do
			local button = entry.Button
			local focused = (button == hovered or button == selected) and available(button)
			if focused then
				-- The artwork is centred in the button, which never scales itself.
				entry.Limit = HoverRoom.Fit(button, Config.HoverScale, CENTER)
			end
			local scale = if entry.Pressed then Config.PressScale elseif focused then entry.Limit else 1
			entry.Motion:spring(scale)
			entry.Glow:spring(if focused or entry.Pressed then 1 else 0)
		end
	end

	local function reset(): ()
		hovered, selected = nil, nil
		for _, entry in entries do
			entry.Pressed = nil
			entry.Motion:spring(1)
			entry.Motion:setPosition(1)
			entry.Motion:setVelocity(0)
			entry.Glow:spring(0)
			entry.Glow:setPosition(0)
			entry.Glow:setVelocity(0)
			-- An already-idle spring need not emit another onChange.
			entry.Scaler.Scale = 1
			if entry.Highlight then
				entry.Highlight.Visible = false
			end
		end
	end

	for _, button in buttons do
		local entry = wrapArtwork(button, owner)
		table.insert(entries, entry)
		owner:Add(
			button.MouseEnter:Connect(function(): ()
				hovered = if available(button) then button else nil
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.MouseLeave:Connect(function(): ()
				if hovered == button then
					hovered = nil
				end
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.SelectionGained:Connect(function(): ()
				selected = if available(button) then button else nil
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.SelectionLost:Connect(function(): ()
				if selected == button then
					selected = nil
				end
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.InputBegan:Connect(function(input: InputObject): ()
				if not Press.IsClick(input) or not available(button) then
					return
				end
				entry.Pressed = input
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(button:GetPropertyChangedSignal("Visible"):Connect(reset), "Disconnect")
		owner:Add(button:GetPropertyChangedSignal("Interactable"):Connect(reset), "Disconnect")
	end

	-- Release outside a slot still clears its touch/mouse press.
	owner:Add(
		UserInputService.InputEnded:Connect(function(input: InputObject): ()
			if not Press.IsClick(input) then
				return
			end
			for _, entry in entries do
				if entry.Pressed == input then
					entry.Pressed = nil
				end
			end
			refresh()
		end),
		"Disconnect"
	)
	owner:Add(UserInputService.WindowFocusReleased:Connect(reset), "Disconnect")

	-- Hidden screens/rows need no MouseLeave to return to rest, including Next Day.
	local ancestor: Instance? = row
	while ancestor do
		if ancestor:IsA("GuiObject") then
			owner:Add(ancestor:GetPropertyChangedSignal("Visible"):Connect(reset), "Disconnect")
		elseif ancestor:IsA("LayerCollector") then
			owner:Add(ancestor:GetPropertyChangedSignal("Enabled"):Connect(reset), "Disconnect")
		end
		ancestor = ancestor.Parent
	end
	owner:LinkToInstance(row)
	return owner
end

return ButtonRow
