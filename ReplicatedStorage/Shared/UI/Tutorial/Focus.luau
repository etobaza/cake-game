--!strict
-- Tutorial target adapter. Generic Hint owns rendering, animation and lifetime arbitration.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Geometry = require(script.Parent.Geometry)
local Hint = require(script.Parent.Parent.Hint)
local Prompt = require(ReplicatedStorage.Handlers.PromptHandler)
local Targets = require(script.Parent.Targets)
local Types = require(ReplicatedStorage.Shared.GameTypes)

local Focus = {}
Focus.__index = Focus
export type Focus = typeof(setmetatable(
	{} :: {
		Hint: Hint.View,
		Target: Targets.Target?,
		Spec: Types.TutorialTarget?,
		GoalGui: GuiObject?,
		PromptBounds: Geometry.Rect?,
	},
	Focus
))

function Focus.new(screen: ScreenGui): Focus
	-- Retire the old tutorial-specific pointer without changing the authored screen.
	for _, name in { "Hole", "Outline", "Direction", "Cursor" } do
		local object = screen:FindFirstChild(name)
		if object and object:IsA("GuiObject") then
			object.Visible = false
		end
	end
	return setmetatable({ Hint = Hint.new({ Priority = Config.TutorialPriority }) }, Focus) :: Focus
end

function Focus.Hide(self: Focus): ()
	self.Hint:SetEnabled(false)
	self.GoalGui, self.PromptBounds = nil, nil
end

function Focus.Resolve(self: Focus, spec: Types.TutorialTarget?): ()
	self.Spec = spec
	local camera = workspace.CurrentCamera
	self.Target = if camera then Targets.Resolve(spec, camera.ViewportSize) else nil
end

function Focus.Update(self: Focus): (Geometry.Rect?, string?)
	local target, spec = self.Target, self.Spec
	local camera = workspace.CurrentCamera
	self.GoalGui, self.PromptBounds = nil, nil
	if not target or not spec or not camera then
		self:Hide()
		return nil, nil
	end
	local key = `{spec.kind}:{spec.id}:{spec.seat or 0}:{spec.control or ""}`
	self.Hint:SetEnabled(true)
	if target.gui then
		self.GoalGui = target.gui
		self.Hint:Gui(target.gui, { Key = key })
		return Geometry.Gui(target.gui, camera.ViewportSize), target.message
	end
	local prompt, billboard, root = Prompt:GetActiveView()
	if prompt and prompt.Parent == target.part and billboard and billboard.Enabled and root then
		self.PromptBounds = Geometry.Gui(root, camera.ViewportSize)
	end
	-- Keep the hand at the exact seat/output when supplied, otherwise at the interaction anchor.
	local point: Hint.WorldTarget? = if target.frame then target.frame.Position else target.part
	if not point then
		self:Hide()
		return nil, target.message
	end
	self.Hint:World(point, { Key = key, WorldOffset = Vector3.new(0, 0.6, 0) })
	local message = target.message
	if self.Hint:IsVisible() and not self.Hint:IsOnScreen() then
		message = "Follow the hand to the object"
	elseif self.Hint.Occluded then
		message = "Walk around the obstacle toward the hand"
	end
	return self.Hint:GetBounds(), message
end

function Focus.Destroy(self: Focus): ()
	self.Hint:Destroy()
end

return Focus
