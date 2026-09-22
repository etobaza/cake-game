--!strict
-- Motion for the HUD, built on Ripple: springs that own one property of one element.
-- Screens ask for an effect ("pop this", "fill that"), the tuning lives here and nowhere else.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Libs = _Shared.Libs

--[[ Modules ]]--
local Ripple = require(_Libs.Ripple)

--[[ Constants ]]--
-- Snappy overshoot for anything that appears or reacts to a press.
local POP_SPRING = { frequency = 5, dampingRatio = 0.55 }
-- Bars and slides settle without bouncing: a wobbling progress bar reads as a glitch.
local SMOOTH_SPRING = { frequency = 4, dampingRatio = 1 }
local POP_FROM = 0.7
-- A hanging-sign wobble: how far the kick tilts, and a loose spring so it swings a few times.
local SWING_SPRING = { frequency = 3, dampingRatio = 0.3 }
local SWING_DEGREES = 12
local PRESS_SCALE = 0.92
local HOVER_SCALE = 1.12
local ENTER_RISE = 24
-- Remembered left edge of a bar fill: the authored bars start outside the rounded frame, so the
-- fill grows around that edge and the edge itself must not be re-measured from a moving size.
local FILL_LEFT = "FillLeft"
-- What counts as a press. Same set Shared/UI/Press uses, for the same reason.
local PRESS_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

--[[ Private Variables ]]--
-- Every motion is created with `start = true`: an unstarted one never joins Ripple's Heartbeat and
-- the property stays wherever the first setPosition left it.
-- One motion per element per property. A second motion on the same property would fight the first.
local Scales: { [GuiObject]: any } = setmetatable({}, { __mode = "k" }) :: any
local ScaleBases: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local Rises: { [GuiObject]: any } = setmetatable({}, { __mode = "k" }) :: any
local RiseOffsets: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local Fills: { [GuiObject]: any } = setmetatable({}, { __mode = "k" }) :: any
-- How wide a fill can grow: 1 minus its hidden left edge.
local Spans: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local Counts: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
-- Bumped every time an element enters or leaves, so a finished exit knows whether it is still the
-- current one before it hides anything.
local ExitTokens: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local Tracked: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

--[[ Tables ]]--
local Animate = {}

--[[ Private Functions ]]--
local function GetScaler(element: GuiObject): UIScale
	local existing = element:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end

	local scaler = Instance.new("UIScale")
	scaler.Parent = element

	return scaler
end

-- Fit written by SetLayoutScale; an element that was never fitted keeps its authored scale.
local function GetLayoutScale(element: GuiObject): number
	return (element:GetAttribute("LayoutScale") :: number?) or 1
end

--[[ Handling ]]--
-- The scale spring is a multiplier of the authored UIScale, so opening or pressing an element
-- preserves its designed size. Callers use 1 for rest and 0 for fully hidden.
function Animate.Scale(element: GuiObject): any
	local existing = Scales[element]
	if existing then
		return existing
	end

	local scaler = GetScaler(element)
	local baseScale = scaler.Scale
	ScaleBases[element] = baseScale
	local motion = Ripple.createMotion(1, { start = true, spring = POP_SPRING })

	motion:onChange(function(value: number)
		scaler.Scale = baseScale * GetLayoutScale(element) * value
	end)

	Scales[element] = motion

	return motion
end

-- Fit and animation share one UIScale. Resizing must preserve the current spring progress.
function Animate.SetLayoutScale(element: GuiObject, scale: number): ()
	local motion = Animate.Scale(element)
	element:SetAttribute("LayoutScale", scale)
	GetScaler(element).Scale = ScaleBases[element] * scale * motion:getPosition()
end

-- A punch: jumps to a smaller scale and springs back to normal.
function Animate.Pop(element: GuiObject, from: number?): ()
	local motion = Animate.Scale(element)

	motion:setPosition(from or POP_FROM)
	motion:spring(1)
end

-- A hanging-sign wobble: tilts the element and lets it swing back to rest.
function Animate.Swing(element: GuiObject, degrees: number?): ()
	local motion = Animate.Track(element, "Rotation", 0, function(value: number)
		element.Rotation = value
	end)

	motion:setPosition(degrees or SWING_DEGREES)
	motion:spring(0, SWING_SPRING)
end

-- Appearing element: pops up and rides in from slightly below its resting spot.
function Animate.Enter(element: GuiObject, rise: number?): ()
	-- Cancels a leave that is still running, so a page reopened mid-exit does not hide itself.
	ExitTokens[element] = (ExitTokens[element] or 0) + 1

	local motion = Rises[element]

	if not motion then
		local base = element.Position

		motion = Ripple.createMotion(0, { start = true, spring = POP_SPRING })
		motion:onChange(function(value: number)
			RiseOffsets[element] = value
			element.Position = ((element:GetAttribute("RestPosition") :: UDim2?) or base) + UDim2.fromOffset(0, value)
		end)

		Rises[element] = motion
	end

	motion:setPosition(rise or ENTER_RISE)
	motion:spring(0)

	Animate.Pop(element)
end

-- Layout supplies the resting point; the animation keeps its current rise offset.
function Animate.Place(element: GuiObject, position: UDim2): ()
	element:SetAttribute("RestPosition", position)
	element.Position = position + UDim2.fromOffset(0, RiseOffsets[element] or 0)
end

-- Leaving element: shrinks away. The caller hides it once the spring has run.
function Animate.Exit(element: GuiObject): ()
	ExitTokens[element] = (ExitTokens[element] or 0) + 1
	Animate.Scale(element):spring(0, SMOOTH_SPRING)
end

-- Leaving element that has to be switched off afterwards -- a page turning its ScreenGui back off.
-- `done` runs when the spring lands, and never if the element came back in the meantime.
function Animate.ExitThen(element: GuiObject, done: () -> ()): ()
	Animate.Exit(element)

	local token = ExitTokens[element]
	local motion = Animate.Scale(element)
	local disconnect: (() -> ())? = nil

	disconnect = motion:onComplete(function()
		if disconnect then
			disconnect()
		end

		if ExitTokens[element] == token then
			done()
		end
	end)
end

-- Press feedback for anything the player can hit. Reads raw input rather than MouseButton1Down, so
-- it works on the frames the screens were drawn with as well as on real buttons -- and on touch,
-- where there is no hover at all.
--
-- The scale goes on `target` when the hitbox is a bare button over an artwork frame, which is how
-- the HUD side buttons are built.
-- Returns a reset callback for owners that hide/reuse their controls without a MouseLeave.
function Animate.Press(hitbox: GuiObject, target: GuiObject?, owner: any?): () -> ()
	-- Close buttons keep their artwork and responsive geometry inside a centered wrapper.
	-- Animate that wrapper while the button continues to own input and visibility.
	local wrapper = hitbox.Parent
	local element = target
		or (if wrapper and wrapper:IsA("GuiObject") and wrapper:GetAttribute("CloseWrapper") then wrapper else hitbox)
	-- The first binding for an element owns its scale motion and returns it to rest on cleanup.
	local motionOwner = if Scales[element] == nil then owner else nil
	local authoredScaler = element:FindFirstChildOfClass("UIScale")
	local motion = Animate.Scale(element)
	local hovering = false
	local function own(connection: RBXScriptConnection): ()
		if owner then
			owner:Add(connection, "Disconnect")
		end
	end
	if motionOwner then
		motionOwner:Add(function(): ()
			motion:destroy()
			Scales[element] = nil
			local scaler = element:FindFirstChildOfClass("UIScale")
			if scaler then
				if authoredScaler then
					scaler.Scale = ScaleBases[element]
				else
					scaler:Destroy()
				end
			end
			ScaleBases[element] = nil
		end, true)
	end

	hitbox.Active = true

	own(hitbox.InputBegan:Connect(function(input: InputObject)
		if PRESS_INPUTS[input.UserInputType] then
			motion:spring(PRESS_SCALE)
		end
	end))

	own(hitbox.InputEnded:Connect(function(input: InputObject)
		if PRESS_INPUTS[input.UserInputType] then
			motion:spring(if hovering then HOVER_SCALE else 1)
		end
	end))

	own(hitbox.MouseEnter:Connect(function()
		hovering = true
		motion:spring(HOVER_SCALE)
	end))

	own(hitbox.MouseLeave:Connect(function()
		hovering = false
		motion:spring(1)
	end))

	return function(): ()
		hovering = false
		motion:spring(1)
		motion:setPosition(1)
		motion:setVelocity(0)
		-- An already-idle spring need not emit another onChange. Restore the rendered scale now.
		GetScaler(element).Scale = ScaleBases[element] * GetLayoutScale(element)
	end
end

-- Same thing for a real button, kept because the parent is the artwork by convention there.
function Animate.Button(button: GuiButton, target: GuiObject?): ()
	Animate.Press(button, target or button.Parent :: GuiObject)
end

-- Progress bar fill, 0..1, springing to the new width instead of jumping to it.
function Animate.Fill(fill: GuiObject, ratio: number): ()
	local motion = Fills[fill]

	if not motion then
		local left = fill:GetAttribute(FILL_LEFT) :: number?
		if not left then
			left = fill.Position.X.Scale - fill.Size.X.Scale / 2
			fill:SetAttribute(FILL_LEFT, left)
		end

		local edge: number = left :: number
		local height = fill.Size.Y

		motion = Ripple.createMotion(fill.Size.X.Scale, { start = true, spring = SMOOTH_SPRING })
		motion:onChange(function(value: number)
			fill.Size = UDim2.new(value, 0, height.Scale, height.Offset)
			fill.Position = UDim2.new(edge + value / 2, 0, fill.Position.Y.Scale, fill.Position.Y.Offset)
		end)

		Fills[fill] = motion
		Spans[fill] = 1 - edge
	end

	motion:spring(Spans[fill] * math.clamp(ratio, 0, 1))
end

-- A spring the caller drives itself, one per property name: for what this module has no opinion
-- about, like where a collapsed panel parks its arrow.
function Animate.Track(key: Instance, property: string, initial: number, write: (number) -> ()): any
	local springs = Tracked[key]
	if not springs then
		springs = {}
		Tracked[key] = springs
	end

	local motion = springs[property]
	if motion then
		return motion
	end

	motion = Ripple.createMotion(initial, { start = true, spring = SMOOTH_SPRING })
	motion:onChange(write)
	springs[property] = motion

	return motion
end

-- A number that counts to its new value instead of snapping. `write` draws it.
function Animate.Count(key: Instance, value: number, write: (number) -> (), decimals: number?): ()
	local motion = Counts[key]

	if not motion then
		local precision = 10 ^ (decimals or 0)
		motion = Ripple.createMotion(value, { start = true, spring = SMOOTH_SPRING })
		motion:onChange(function(current: number)
			write(math.round(current * precision) / precision)
		end)

		Counts[key] = motion
		write(value)
	end

	motion:spring(value)
end

return Animate
