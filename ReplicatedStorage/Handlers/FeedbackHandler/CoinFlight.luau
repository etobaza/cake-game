--!strict
-- Coins that pop out of a sale point and curve into the HUD balance. A coin "lands" once it reaches
-- the target; its callback releases that coin's share of the held balance.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.Feedback)
local Ease = require(ReplicatedStorage.Shared.UI.Ease)

--[[ Types ]]--
type Coin = {
	Label: ImageLabel,
	Scaler: UIScale,
	StartAt: number,
	Origin: Vector2,
	Velocity: Vector2,
	LaunchSeconds: number,
	FlightSeconds: number,
	Spin: number,
	-- Where the ballistic pop ended and how fast it was moving, fixed on the first homing frame.
	Peak: Vector2?,
	Carry: Vector2?,
	Land: () -> (),
}

--[[ Constants ]]--
local RANDOM = Random.new()
local TUNING = Config.Coins
-- The opening pop overshoots slightly before the coin settles to full size.
local POP_SECONDS = 0.14
local POP_STRENGTH = 1.6
-- Coins shrink into the counter over the last part of the flight.
local SHRINK_FROM = 0.7
local LANDING_SCALE = 0.65
-- Half-width of the launch fan around straight up, in radians.
local FAN = 1.2
-- The homing curve bows out at most this share of the remaining distance.
local MAX_BEND = 0.5
local MIN_SIZE, MAX_SIZE = 26, 52

--[[ Tables ]]--
local CoinFlight = {}
CoinFlight.__index = CoinFlight

export type CoinFlight = typeof(setmetatable(
	{} :: {
		Root: GuiObject,
		-- Absolute centre and size of the HUD coin, or nil while it is hidden.
		Target: () -> (Vector2?, Vector2?),
		Coins: { Coin },
		Scale: number,
	},
	CoinFlight
))

--[[ Private Functions ]]--
local function range(value: NumberRange): number
	return RANDOM:NextNumber(value.Min, value.Max)
end

local function bezier(from: Vector2, control: Vector2, to: Vector2, t: number): Vector2
	local inverse = 1 - t
	return from * (inverse * inverse) + control * (2 * inverse * t) + to * (t * t)
end

--[[ Handling ]]--
function CoinFlight.new(root: GuiObject, target: () -> (Vector2?, Vector2?)): CoinFlight
	return setmetatable({ Root = root, Target = target, Coins = {}, Scale = 1 }, CoinFlight)
end

--- Launch speeds and fallback size follow the screen; the owner updates this with the viewport.
function CoinFlight.SetScale(self: CoinFlight, scale: number): ()
	self.Scale = scale
end

function CoinFlight.Count(self: CoinFlight): number
	return #self.Coins
end

--- Launches `count` coins from absolute screen point `origin`. `land(index)` runs as each arrives.
function CoinFlight.Launch(self: CoinFlight, origin: Vector2, count: number, land: (index: number) -> ()): ()
	local now = os.clock()
	local localOrigin = origin - self.Root.AbsolutePosition
	local _, targetSize = self.Target()
	-- Match the HUD coin so the flight reads as the same coin arriving.
	local size = if targetSize then math.clamp(targetSize.Y, MIN_SIZE, MAX_SIZE) else TUNING.Size * self.Scale
	for index = 1, count do
		local angle = -math.pi / 2 + RANDOM:NextNumber(-FAN, FAN)
		local label = Instance.new("ImageLabel")
		label.Name = "Coin"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundTransparency = 1
		label.Image = TUNING.Image
		label.ScaleType = Enum.ScaleType.Fit
		label.Size = UDim2.fromOffset(size, size)
		label.Visible = false
		label.Active = false
		label.ZIndex = 30
		local scaler = Instance.new("UIScale")
		scaler.Scale = 0
		scaler.Parent = label
		label.Parent = self.Root
		local coinIndex = index
		table.insert(self.Coins, {
			Label = label,
			Scaler = scaler,
			StartAt = now + (index - 1) * TUNING.Stagger,
			Origin = localOrigin,
			Velocity = Vector2.new(math.cos(angle), math.sin(angle)) * range(TUNING.LaunchSpeed) * self.Scale,
			LaunchSeconds = range(TUNING.LaunchSeconds),
			FlightSeconds = range(TUNING.FlightSeconds),
			Spin = range(TUNING.Spin),
			Peak = nil,
			Carry = nil,
			Land = function(): ()
				land(coinIndex)
			end,
		})
	end
end

function CoinFlight.Step(self: CoinFlight, now: number): ()
	if #self.Coins == 0 then
		return
	end
	local target = self.Target()
	local localTarget = if target then target - self.Root.AbsolutePosition else nil
	local gravity = Vector2.new(0, TUNING.Gravity * self.Scale)
	for index = #self.Coins, 1, -1 do
		local coin = self.Coins[index]
		local age = now - coin.StartAt
		if age < 0 then
			continue
		end

		local position: Vector2
		local scale = Ease.OutBack(age / POP_SECONDS, POP_STRENGTH)
		if age < coin.LaunchSeconds then
			position = coin.Origin + coin.Velocity * age + gravity * (0.5 * age * age)
		else
			if not coin.Peak then
				local launch = coin.LaunchSeconds
				coin.Peak = coin.Origin + coin.Velocity * launch + gravity * (0.5 * launch * launch)
				coin.Carry = coin.Velocity + gravity * launch
			end
			local progress = (age - coin.LaunchSeconds) / coin.FlightSeconds
			if progress >= 1 or not localTarget then
				coin.Label:Destroy()
				table.remove(self.Coins, index)
				coin.Land()
				continue
			end
			-- The launch velocity bends the path, never further than half the flight; squared time
			-- accelerates the coin into the counter.
			local peak = coin.Peak :: Vector2
			local carry = coin.Carry :: Vector2
			local bend = math.min(carry.Magnitude * TUNING.Arc, (localTarget - peak).Magnitude * MAX_BEND)
			local control = if carry.Magnitude > 0 then peak + carry.Unit * bend else peak
			position = bezier(peak, control, localTarget, Ease.InQuad(progress))
			if progress > SHRINK_FROM then
				scale *= 1 + (LANDING_SCALE - 1) * (progress - SHRINK_FROM) / (1 - SHRINK_FROM)
			end
		end

		local label = coin.Label
		label.Visible = true
		label.Position = UDim2.fromOffset(position.X, position.Y)
		label.Rotation = coin.Spin * age
		coin.Scaler.Scale = scale
	end
end

--- Lands every remaining coin at once, releasing all held balance.
function CoinFlight.Clear(self: CoinFlight): ()
	local coins = self.Coins
	self.Coins = {}
	for _, coin in coins do
		coin.Label:Destroy()
		coin.Land()
	end
end

function CoinFlight.Destroy(self: CoinFlight): ()
	self:Clear()
end

return CoinFlight
