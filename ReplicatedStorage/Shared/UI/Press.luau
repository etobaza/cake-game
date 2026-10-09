--!strict
-- Makes a pressable thing out of an authored frame.
--
-- Several screens were drawn without buttons: a node in the upgrade tree, a recipe cell in the day
-- menu and the plates in a footer are all plain frames. Adding a TextButton over each of them would
-- be layout built in code, so the press is read off the frame itself instead.
--
-- A GuiObject only receives input while it is Active, so binding turns that on.

--[[ Services ]]--
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Constants ]]--
local TAP_DISTANCE = 10
local CLICK_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

--[[ Tables ]]--
local Press = {}

--[[ Private Functions ]]--
local function available(object: GuiObject): boolean
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return object:IsDescendantOf(game) and object.Active and object.Interactable
end

local function bindGamepad(object: GuiObject, callback: () -> (), janitor: any): ()
	object.Selectable = true
	local armed = false
	janitor:Add(
		UserInputService.InputBegan:Connect(function(input: InputObject): ()
			if input.KeyCode == Enum.KeyCode.ButtonA then
				armed = GuiService.SelectedObject == object
					and available(object)
					and not GuiService.MenuIsOpen
					and UserInputService:GetFocusedTextBox() == nil
			end
		end),
		"Disconnect"
	)
	janitor:Add(
		UserInputService.InputEnded:Connect(function(input: InputObject): ()
			if input.KeyCode ~= Enum.KeyCode.ButtonA then
				return
			end
			local activate = armed and GuiService.SelectedObject == object and available(object)
			armed = false
			if activate and not GuiService.MenuIsOpen then
				callback()
			end
		end),
		"Disconnect"
	)
	janitor:Add(
		object.SelectionLost:Connect(function(): ()
			armed = false
		end),
		"Disconnect"
	)
	janitor:Add(
		UserInputService.WindowFocusReleased:Connect(function(): ()
			armed = false
		end),
		"Disconnect"
	)
end

--[[ Handling ]]--
--- True for the inputs that count as a press on interface.
function Press.IsClick(input: InputObject): boolean
	return CLICK_TYPES[input.UserInputType] == true
end

--- Keeps a world-space plate Active only while the player is not on mouse and keyboard. An Active
--- GuiObject sinks the right button and the wheel, so the camera stops turning and zooming under
--- the cursor; the frame's own InputBegan still fires without Active, so mouse clicks keep working.
--- Touch needs Active so a tap does not also steer the camera, and the gamepad binding reads it.
--- Call after Bind/BindTap, which turn Active on.
function Press.SinkUnlessMouse(object: GuiObject): any
	local janitor = Janitor.new()
	local function apply(): ()
		object.Active = UserInputService.PreferredInput ~= Enum.PreferredInput.KeyboardAndMouse
	end
	apply()
	janitor:Add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(apply), "Disconnect")
	janitor:LinkToInstance(object)
	return janitor
end

--- Owns pointer and gamepad bindings until the returned Janitor or object is destroyed.
function Press.Bind(object: GuiObject, callback: () -> ()): any
	local janitor = Janitor.new()
	object.Active = true
	bindGamepad(object, callback, janitor)
	janitor:Add(
		object.InputBegan:Connect(function(input: InputObject)
			if Press.IsClick(input) then
				callback()
			end
		end),
		"Disconnect"
	)
	janitor:LinkToInstance(object)
	return janitor
end

-- Scrollable cards commit on release, and only if the gesture stayed a tap.
-- The returned Janitor also cancels an in-flight gesture when the card dies.
function Press.BindTap(object: GuiObject, callback: () -> ()): any
	local janitor = Janitor.new()
	local pressed: InputObject? = nil
	local origin = Vector2.zero
	local cancelled = false
	object.Active = true
	bindGamepad(object, callback, janitor)
	janitor:Add(
		object.InputBegan:Connect(function(input: InputObject)
			if not Press.IsClick(input) or pressed then
				return
			end
			pressed = input
			origin = Vector2.new(input.Position.X, input.Position.Y)
			cancelled = false
		end),
		"Disconnect"
	)
	janitor:Add(
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not pressed then
				return
			end
			if input ~= pressed and input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local position = Vector2.new(input.Position.X, input.Position.Y)
			cancelled = cancelled or (position - origin).Magnitude > TAP_DISTANCE
		end),
		"Disconnect"
	)
	janitor:Add(
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input ~= pressed then
				return
			end
			pressed = nil
			local point = Vector2.new(input.Position.X, input.Position.Y)
			local playerGui = object:FindFirstAncestorWhichIsA("PlayerGui")
			if cancelled or not playerGui then
				return
			end
			-- Hit testing includes scrolling clips, hidden ancestors and other windows.
			for _, hit in playerGui:GetGuiObjectsAtPosition(point.X, point.Y) do
				if hit == object or hit:IsDescendantOf(object) then
					callback()
					return
				end
				if hit.Active and not object:IsDescendantOf(hit) then
					return
				end
			end
		end),
		"Disconnect"
	)
	janitor:LinkToInstance(object)
	return janitor
end

return Press
