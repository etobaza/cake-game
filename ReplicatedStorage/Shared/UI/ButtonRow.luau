--!strict
-- Stable authored hitboxes contain centered artwork wrappers. Only their artwork shrinks.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]
--
local Config = require(ReplicatedStorage.Shared.Configs.ButtonRow)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Press = require(script.Parent.Press)
local Ripple = require(ReplicatedStorage.Shared.Libs.Ripple)

--[[ Types ]]
--
type Entry = {
	Button: GuiObject,
	Scaler: UIScale,
	Motion: Ripple.Motion<number>,
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
	local motion = Ripple.createMotion(1, {
		start = true,
		spring = { frequency = Config.Spring.frequency, dampingRatio = Config.Spring.dampingRatio },
	})
	motion:onChange(function(value: number): ()
		-- Fast reversals must never push artwork outside the authored slot.
		scaler.Scale = math.clamp(value, 0, 1)
	end)
	local wasActive = button.Active
	button.Active = true
	owner:Add(function(): ()
		motion:destroy()
		if button.Parent then
			button.Active = wasActive
			moveArtwork(wrapper, button)
		end
		wrapper:Destroy()
	end, true)

	return { Button = button, Scaler = scaler, Motion = motion, Pressed = nil }
end

--[[ Handling ]]
--
-- The supplied controls are transparent authored containers; Bg/Txt/Icon carry their artwork.
-- Keep the controls in place so routing, layout, touch targets and selection remain stable.
function ButtonRow.Bind(row: GuiObject, buttons: { GuiObject }): Janitor.Janitor
	local owner = Janitor.new()
	local entries: { Entry } = {}
	local hovered: Entry? = nil
	local selected: Entry? = nil
	local pressed: Entry? = nil

	local function refresh(): ()
		local focused = pressed or hovered or selected
		if focused and not available(focused.Button) then
			focused = nil
		end
		for _, entry in entries do
			local scale = 1
			if focused and entry ~= focused then
				scale = Config.NeighborScale
			elseif entry.Pressed then
				scale = Config.PressScale
			end
			entry.Motion:spring(scale)
		end
	end

	local function reset(): ()
		hovered, selected, pressed = nil, nil, nil
		for _, entry in entries do
			entry.Pressed = nil
			entry.Motion:spring(1)
			entry.Motion:setPosition(1)
			entry.Motion:setVelocity(0)
			entry.Scaler.Scale = 1
		end
	end

	for _, button in buttons do
		local entry = wrapArtwork(button, owner)
		table.insert(entries, entry)
		owner:Add(
			button.MouseEnter:Connect(function(): ()
				hovered = if available(button) then entry else nil
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.MouseLeave:Connect(function(): ()
				if hovered == entry then
					hovered = nil
				end
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.SelectionGained:Connect(function(): ()
				selected = if available(button) then entry else nil
				refresh()
			end),
			"Disconnect"
		)
		owner:Add(
			button.SelectionLost:Connect(function(): ()
				if selected == entry then
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
				pressed = entry
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
				if entry.Pressed ~= input then
					continue
				end
				entry.Pressed = nil
				if pressed == entry then
					pressed = nil
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
