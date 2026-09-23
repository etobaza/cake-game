--!strict
-- Tutorial target adapter. Generic Hint owns rendering, animation and lifetime arbitration.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Hint = require(script.Parent.Parent.Hint)
local Targets = require(script.Parent.Targets)
local Types = require(ReplicatedStorage.Shared.GameTypes)

local Focus = {}
Focus.__index = Focus
export type Focus = typeof(setmetatable(
	{} :: {
		Hint: Hint.View,
		Target: Targets.Target?,
		Spec: Types.TutorialTarget?,
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
end

function Focus.Resolve(self: Focus, spec: Types.TutorialTarget?): ()
	self.Spec = spec
	local camera = workspace.CurrentCamera
	self.Target = if camera then Targets.Resolve(spec, camera.ViewportSize) else nil
end

function Focus.Update(self: Focus): ()
	local target, spec = self.Target, self.Spec
	local camera = workspace.CurrentCamera

	if not target or not spec or not camera then
		self:Hide()
		return
	end

	local key = `{spec.kind}:{spec.id}:{spec.seat or 0}:{spec.control or ""}`
	self.Hint:SetEnabled(true)

	if target.gui then
		self.Hint:Gui(target.gui, { Key = key })
		return
	end

	-- Keep the hand at the exact seat/output when supplied, otherwise at the interaction anchor.
	local point: Hint.WorldTarget? = if target.frame then target.frame.Position else target.part
	if not point then
		self:Hide()
		return
	end

	self.Hint:World(point, { Key = key, WorldOffset = Config.TutorialWorldOffset })
end

function Focus.Destroy(self: Focus): ()
	self.Hint:Destroy()
end

return Focus
