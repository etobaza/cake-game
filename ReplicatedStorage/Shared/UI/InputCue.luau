--!strict
-- A controller glyph on a button and the gamepad button that presses it. The badge shows the
-- connected controller's own art (UserInputService serves Xbox or PlayStation) and only while a
-- gamepad is the input in use; PC and touch see nothing. A shortcut only fires while its button is
-- on screen, so a cue never presses something the player cannot see.

--[[ Services ]]--
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Authored = require(script.Parent.Authored)
local Config = require(ReplicatedStorage.Shared.Configs.InputCues)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(script.Parent.Stores.Pages)
local Theme = require(script.Parent.Theme)

--[[ Types ]]--
-- Corner: over the bottom-right corner. Edge / LeftEdge: over the right / left edge's middle.
-- Left / Right: beside the button.
export type Placement = "Corner" | "Edge" | "LeftEdge" | "Left" | "Right"

export type Spec = {
	-- Names the ContextActionService action, so it is unique per cue and required with an Action.
	Name: string?,
	Target: GuiObject,
	Key: Enum.KeyCode,
	-- Without an action the badge only labels a button another system handles (B closes pages).
	Action: (() -> ())?,
	-- Replaces the default check that Target is on screen.
	Available: (() -> boolean)?,
	-- Hides the badge while false; the owner calls Cue:Refresh when it may have changed.
	Shown: (() -> boolean)?,
	Placement: Placement?,
}

export type Cue = {
	-- Redraws the badge, e.g. after Spec.Shown changed.
	Refresh: (self: Cue) -> (),
	Destroy: (self: Cue) -> (),
}

--[[ Constants ]]--
local BADGE = Config.Badge
local ACTION_PREFIX = "CakeCue"
-- Above NavigationHandler's High-priority X sink, so a page's own X wins while it is open.
local PRIORITY = Enum.ContextActionPriority.High.Value + 10
-- With a gamepad selection up, the D-pad moves it instead of pressing shortcuts.
local NAVIGATION: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadDown] = true,
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true,
}

--[[ Tables ]]--
local InputCue = {}

--[[ Private Functions ]]--
local function place(badge: Frame, placement: Placement, size: number): ()
	local inset = size * BADGE.Inset
	if placement == "Corner" then
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(1, -inset, 1, -inset)
	elseif placement == "Edge" then
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(1, -inset, 0.5, 0)
	elseif placement == "LeftEdge" then
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(0, inset, 0.5, 0)
	elseif placement == "Left" then
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.new(0, -BADGE.SideGap, 0.5, 0)
	else
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(1, BADGE.SideGap, 0.5, 0)
	end
end

-- An empty, hidden badge. InputCue.Render fills it.
local function newBadge(): Frame
	local badge = Instance.new("Frame")
	badge.Name = "InputCue"
	-- A dark disc with a light glyph, like the controller's own buttons; the light rim keeps it
	-- apart from dark artwork it overlaps.
	badge.BackgroundColor3 = Theme.Colors.Cocoa
	badge.BorderSizePixel = 0
	badge.Selectable = false
	badge.Visible = false
	badge.ZIndex = BADGE.ZIndex

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.PanelFill
	stroke.Thickness = BADGE.Stroke
	stroke.Parent = badge

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.BackgroundTransparency = 1
	glyph.ImageColor3 = Theme.Colors.PanelFill
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.Size = UDim2.fromScale(BADGE.GlyphShare, BADGE.GlyphShare)
	glyph.ZIndex = BADGE.ZIndex + 1
	glyph.Parent = badge

	return badge
end

local function ready(spec: Spec, key: Enum.KeyCode): boolean
	if Pages.Presenting:peek() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then
		return false
	end
	if NAVIGATION[key] and GuiService.SelectedObject ~= nil then
		return false
	end
	return if spec.Available then spec.Available() else InputCue.OnScreen(spec.Target)
end

--[[ Handling ]]--
--- Whether `object` is drawn: it and every ancestor are visible and its screen is enabled.
function InputCue.OnScreen(object: GuiObject): boolean
	if not object:IsDescendantOf(game) or object.AbsoluteSize.X <= 0 then
		return false
	end
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
	return true
end

--- Shows `key`'s glyph on `badge` at `size` layout pixels across, or hides it without one. The
--- badge needs a `Glyph` ImageLabel.
function InputCue.Render(badge: Frame, key: Enum.KeyCode?, size: number): ()
	badge.Visible = key ~= nil
	if key then
		badge.Size = UDim2.fromOffset(math.round(size), math.round(size))
		local glyph = badge:FindFirstChild("Glyph") :: ImageLabel
		glyph.Image = UserInputService:GetImageForKeyCode(key)
	end
end

--- The gamepad focus ring, for PlayerGui.SelectionImageObject. Its stroke sits just outside the
--- selected object; InputCue.FitRing rounds it like that object.
function InputCue.SelectionRing(): Frame
	local ring = Instance.new("Frame")
	ring.Name = "SelectionRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Config.Selection.Corner
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Selection.Color
	stroke.Thickness = Config.Selection.Thickness
	stroke.Parent = ring
	return ring
end

-- The rounding `object` draws: its own UICorner, or the one on art that fills it (a tab's plate).
local function roundingOf(object: GuiObject): (UICorner?, GuiObject?)
	local own = object:FindFirstChildOfClass("UICorner")
	if own then
		return own, object
	end
	local filled = object.AbsoluteSize * Config.Selection.Fill
	for _, descendant in object:GetDescendants() do
		local owner = descendant.Parent
		if
			descendant:IsA("UICorner")
			and owner
			and owner:IsA("GuiObject")
			and owner.AbsoluteSize.X >= filled.X
			and owner.AbsoluteSize.Y >= filled.Y
		then
			return descendant, owner
		end
	end
	return nil, nil
end

--- Rounds the focus ring like `selected`, so it follows the button's outline.
function InputCue.FitRing(ring: Frame, selected: GuiObject): ()
	local corner = ring:FindFirstChildOfClass("UICorner") :: UICorner
	local rounding, owner = roundingOf(selected)
	local side = math.min(selected.AbsoluteSize.X, selected.AbsoluteSize.Y)
	if not rounding or not owner or side <= 0 then
		corner.CornerRadius = Config.Selection.Corner
		return
	end
	local size = owner.AbsoluteSize
	local unscaled = Authored.UnscaledSize(owner)
	local radius = rounding.CornerRadius.Scale * math.min(size.X, size.Y)
		+ rounding.CornerRadius.Offset * (if unscaled.X > 0 then size.X / unscaled.X else 1)
	-- As a share of the side, the radius holds at whatever UIScale the ring is drawn with.
	corner.CornerRadius = UDim.new(math.min(radius / side, 0.5), 0)
end

--- Draws the badge on spec.Target and binds spec.Key to spec.Action. Destroying the returned cue (or
--- the target) removes both.
function InputCue.Bind(spec: Spec): Cue
	local janitor = Janitor.new()
	local target = spec.Target
	local placement: Placement = spec.Placement or "Corner"
	local badge = newBadge()
	janitor:Add(badge, "Destroy")

	-- In layout pixels: the badge draws inside the same UIScales as its button.
	local function size(): number
		local unscaled = Authored.UnscaledSize(target)
		return math.round(math.clamp(math.min(unscaled.X, unscaled.Y) * BADGE.Share, BADGE.MinSize, BADGE.MaxSize))
	end
	local function layout(): ()
		local side = size()
		badge.Size = UDim2.fromOffset(side, side)
		place(badge, placement, side)
	end
	local function refresh(): ()
		local shown = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
			and (spec.Shown == nil or spec.Shown())
		InputCue.Render(badge, if shown then spec.Key else nil, size())
		layout()
	end
	refresh()
	badge.Parent = target
	janitor:Add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh), "Disconnect")
	-- A different controller brand swaps the glyph art.
	janitor:Add(UserInputService.GamepadConnected:Connect(refresh), "Disconnect")
	-- A world-space target resizes every frame the camera moves, so this only lays the badge out.
	janitor:Add(target:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout), "Disconnect")

	local action = spec.Action
	if action then
		local name = ACTION_PREFIX .. assert(spec.Name, "[InputCue] a cue with an Action needs a Name")
		-- The release of a handled press is swallowed too, so nothing below sees half a press.
		local pressed = false
		ContextActionService:BindActionAtPriority(
			name,
			function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
				if state == Enum.UserInputState.Begin then
					pressed = ready(spec, input.KeyCode)
					if pressed then
						action()
					end
					return if pressed then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
				end
				local result = if pressed then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
				if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					pressed = false
				end
				return result
			end,
			false,
			PRIORITY,
			spec.Key
		)
		janitor:Add(function(): ()
			ContextActionService:UnbindAction(name)
		end, true)
	end

	-- The target's removal may clean up first; the cue then ignores further calls.
	local alive = true
	janitor:Add(function(): ()
		alive = false
	end, true)
	janitor:LinkToInstance(target)
	return {
		Refresh = function(_self: Cue): ()
			if alive then
				refresh()
			end
		end,
		Destroy = function(_self: Cue): ()
			if alive then
				janitor:Destroy()
			end
		end,
	}
end

return InputCue
