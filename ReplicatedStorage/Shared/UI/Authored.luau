--!strict
-- Reaching into layout that was drawn in StarterGui.
--
-- The screens are authored, not built, so every handler that drives one has to address elements by
-- the names the artist gave them. Shared helpers keep those lookups and layout coordinates consistent.

--[[ Tables ]]--
local Authored = {}

--[[ Handling ]]--
-- Grid offsets and scrolling offsets are logical pixels; AbsoluteSize includes every UIScale.
function Authored.UnscaledSize(object: GuiObject): Vector2
	local scale = 1
	local current: Instance? = object
	while current and not current:IsA("LayerCollector") do
		local scaler = current:FindFirstChildOfClass("UIScale")
		if scaler then
			scale *= scaler.Scale
		end
		current = current.Parent
	end
	return if scale > 0 then object.AbsoluteSize / scale else Vector2.zero
end

--- Walks a path of child names from `root`. Returns nil as soon as a name is missing, so a screen
--- that was redrawn degrades into a warning instead of an error.
function Authored.Resolve(root: Instance, path: { string }): Instance?
	local current: Instance = root

	for _, segment in path do
		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end

		current = child
	end

	return current
end

--- Outlined text is drawn as a pair: a dark shadow plate and the face on top of it. Writing only one
--- of them makes the shadow drift out from under the text, so both are written together.
function Authored.SetPair(holder: Instance?, text: string): ()
	if not holder then
		return
	end

	for _, child in holder:GetChildren() do
		if child:IsA("TextLabel") then
			child.Text = text
		end
	end
end

--- Every element under `parent` that carries `name`, left to right as drawn. Screens repeat a name
--- for elements that were meant to differ later, and position is the only thing telling them apart.
function Authored.NamedInOrder(parent: Instance, name: string): { GuiObject }
	local found = {}

	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name == name then
			found[#found + 1] = child
		end
	end

	table.sort(found, function(left: GuiObject, right: GuiObject): boolean
		return left.Position.X.Scale < right.Position.X.Scale
	end)

	return found
end

return Authored
