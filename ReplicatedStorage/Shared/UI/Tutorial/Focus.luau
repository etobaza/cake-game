--!strict
-- Tutorial target adapter. Generic Hint owns rendering, animation and lifetime arbitration.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Hint = require(script.Parent.Parent.Hint)
local Interact = require(ReplicatedStorage.Handlers.InteractHandler)
local PromptHandler = require(ReplicatedStorage.Handlers.PromptHandler)
local Geometry = require(script.Parent.Geometry)
local Targets = require(script.Parent.Targets)
local TutorialConfig = require(ReplicatedStorage.Shared.Configs.Tutorial)
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

--- `dim` adds the darkening spotlight around a GUI target; without it only the finger points.
function Focus.Update(self: Focus, dim: boolean?): ()
	local target, spec = self.Target, self.Spec
	local camera = workspace.CurrentCamera

	if not target or not spec or not camera then
		self:Hide()
		return
	end

	local key = `{spec.kind}:{spec.id}:{spec.seat or 0}:{spec.control or ""}`
	self.Hint:SetEnabled(true)

	if target.gui then
		self.Hint:Gui(target.gui, {
			Key = key,
			-- The sign, ribbon and time label extend outside their transparent clock container; an
			-- order card's art grows past its frame on hover and its seat badge sits outside it.
			IncludeDescendants = spec.kind == "Order" or (spec.kind == "Gui" and spec.id == "UI.HUD.Time"),
			-- A small order card needs room around it to stand out from the dimmed HUD.
			Padding = if spec.kind == "Order" then TutorialConfig.OrderFocusPadding else nil,
			Dim = dim ~= false,
		})
		return
	end

	-- Once the exact target is actionable nearby, point at its tappable plate.
	-- Another station's prompt must never steal this lesson's finger. A seat goal's action lives on
	-- that dining place's own prompt target; the table part keeps cleaning.
	local prompt, billboard, root = PromptHandler:GetActiveView()
	local promptPart = prompt and prompt.Parent
	local seatTarget = if target.part and spec.seat then Interact:GetSeatProp(spec.id, spec.seat) else nil
	if
		prompt
		and promptPart
		and promptPart:IsA("BasePart")
		and (promptPart == target.part or promptPart == seatTarget)
		and prompt.Enabled
		and billboard
		and billboard.Enabled
		and root
		and Interact:Describe(promptPart).Fire ~= nil
		and Geometry.Gui(root, camera.ViewportSize)
	then
		self.Hint:Gui(root, { Key = key .. ":prompt", Dim = false })
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
