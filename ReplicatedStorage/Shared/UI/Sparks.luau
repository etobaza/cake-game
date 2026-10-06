--!strict
-- Screen-space confetti and sparkles inside one overlay frame. The owner steps it every frame and
-- destroys it; every piece removes its own label when it expires.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Feedback)

--[[ Types ]]--
type Piece = {
	Label: ImageLabel,
	Position: Vector2,
	Velocity: Vector2,
	Gravity: number,
	Drag: number,
	Rotation: number,
	Spin: number,
	Size: number,
	Age: number,
	Lifetime: number,
	-- Confetti flips edge-on as it tumbles; sparkles swell and shrink instead.
	Flip: number?,
}

--[[ Constants ]]--
local RANDOM = Random.new()
-- The last share of a piece's life fades it out.
local FADE_SHARE = 0.25

--[[ Tables ]]--
local Sparks = {}
Sparks.__index = Sparks

export type Sparks = typeof(setmetatable(
	{} :: {
		Root: GuiObject,
		Pieces: { Piece },
		Scale: number,
	},
	Sparks
))

--[[ Private Functions ]]--
local function range(value: NumberRange): number
	return RANDOM:NextNumber(value.Min, value.Max)
end

local function newLabel(root: GuiObject, image: string, color: Color3): ImageLabel
	local label = Instance.new("ImageLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageColor3 = color
	label.Active = false
	label.ZIndex = 20
	label.Parent = root
	return label
end

--[[ Handling ]]--
function Sparks.new(root: GuiObject): Sparks
	return setmetatable({ Root = root, Pieces = {}, Scale = 1 }, Sparks)
end

--- Pixel sizes and speeds follow the screen; owners update this as the viewport changes.
function Sparks.SetScale(self: Sparks, scale: number): ()
	self.Scale = scale
end

function Sparks.Add(self: Sparks, piece: Piece): ()
	if #self.Pieces >= Config.MaxSparks then
		piece.Label:Destroy()
		return
	end
	table.insert(self.Pieces, piece)
end

--- A fountain of paper at absolute screen point `at`, thrown upward in a `spread`-degree fan.
--- `colors` replaces the party palette, for example with fire colours.
function Sparks.Confetti(self: Sparks, at: Vector2, count: number, spread: number?, colors: { Color3 }?): ()
	local tuning = Config.Confetti
	local palette = colors or tuning.Colors
	local origin = at - self.Root.AbsolutePosition
	local fan = math.rad(spread or 140) / 2
	for _ = 1, count do
		local image = tuning.Images[RANDOM:NextInteger(1, #tuning.Images)]
		local color = palette[RANDOM:NextInteger(1, #palette)]
		local angle = -math.pi / 2 + RANDOM:NextNumber(-fan, fan)
		local speed = range(tuning.Speed) * self.Scale
		self:Add({
			Label = newLabel(self.Root, image, color),
			Position = origin,
			Velocity = Vector2.new(math.cos(angle), math.sin(angle)) * speed,
			Gravity = tuning.Gravity * self.Scale,
			Drag = tuning.Drag,
			Rotation = RANDOM:NextNumber(0, 360),
			Spin = range(tuning.Spin),
			Size = range(tuning.Size) * self.Scale,
			Age = 0,
			Lifetime = range(tuning.Lifetime),
			Flip = RANDOM:NextNumber(4, 9),
		})
	end
end

--- Star glints bursting outward from absolute screen point `at`.
function Sparks.Twinkle(self: Sparks, at: Vector2, count: number, color: Color3?): ()
	local tuning = Config.Sparkle
	local origin = at - self.Root.AbsolutePosition
	for _ = 1, count do
		local angle = RANDOM:NextNumber(0, math.pi * 2)
		self:Add({
			Label = newLabel(self.Root, tuning.Image, color or tuning.Color),
			Position = origin,
			Velocity = Vector2.new(math.cos(angle), math.sin(angle)) * range(tuning.Speed) * self.Scale,
			Gravity = 0,
			Drag = 4,
			Rotation = RANDOM:NextNumber(0, 90),
			Spin = RANDOM:NextNumber(-180, 180),
			Size = range(tuning.Size) * self.Scale,
			Age = 0,
			Lifetime = range(tuning.Lifetime),
			Flip = nil,
		})
	end
end

--- Small glints drifting up from absolute screen point `at`, like embers off a flame.
function Sparks.Embers(self: Sparks, at: Vector2, count: number, color: Color3): ()
	local tuning = Config.Sparkle
	local origin = at - self.Root.AbsolutePosition
	for _ = 1, count do
		local size = range(tuning.Size) * 0.45 * self.Scale
		self:Add({
			Label = newLabel(self.Root, tuning.Image, color),
			Position = origin + Vector2.new(RANDOM:NextNumber(-0.25, 0.25) * size * 3, 0),
			Velocity = Vector2.new(RANDOM:NextNumber(-30, 30), -RANDOM:NextNumber(60, 140)) * self.Scale,
			Gravity = -40 * self.Scale,
			Drag = 1,
			Rotation = RANDOM:NextNumber(0, 90),
			Spin = RANDOM:NextNumber(-120, 120),
			Size = size,
			Age = 0,
			Lifetime = RANDOM:NextNumber(0.5, 0.9),
			Flip = nil,
		})
	end
end

function Sparks.Step(self: Sparks, deltaTime: number): ()
	for index = #self.Pieces, 1, -1 do
		local piece = self.Pieces[index]
		piece.Age += deltaTime
		local life = piece.Age / piece.Lifetime
		if life >= 1 then
			piece.Label:Destroy()
			table.remove(self.Pieces, index)
			continue
		end

		piece.Velocity = piece.Velocity * math.exp(-piece.Drag * deltaTime)
			+ Vector2.new(0, piece.Gravity * deltaTime)
		piece.Position += piece.Velocity * deltaTime
		piece.Rotation += piece.Spin * deltaTime

		local width, height = piece.Size, piece.Size
		if piece.Flip then
			width *= 0.2 + 0.8 * math.abs(math.cos(piece.Age * piece.Flip))
		else
			local swell = math.sin(math.min(life, 1) * math.pi)
			width, height = width * swell, height * swell
		end

		local label = piece.Label
		label.Position = UDim2.fromOffset(piece.Position.X, piece.Position.Y)
		label.Size = UDim2.fromOffset(width, height)
		label.Rotation = piece.Rotation
		label.ImageTransparency = math.clamp((life - (1 - FADE_SHARE)) / FADE_SHARE, 0, 1)
	end
end

function Sparks.Clear(self: Sparks): ()
	for _, piece in self.Pieces do
		piece.Label:Destroy()
	end
	table.clear(self.Pieces)
end

function Sparks.Destroy(self: Sparks): ()
	self:Clear()
end

return Sparks
