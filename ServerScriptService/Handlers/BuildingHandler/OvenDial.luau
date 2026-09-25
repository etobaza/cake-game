--!strict
-- A depth-tested color overlay on the existing clock face; the authored hand stays in front.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.OvenMotion).Dial

local OvenDial = {}
local FULL_TURN = math.pi * 2

local function insideMark(point: Vector2): boolean
	local inside = false
	local previous = Config.MarkOutline[#Config.MarkOutline]
	for _, current in Config.MarkOutline do
		if (current.Y > point.Y) ~= (previous.Y > point.Y) then
			local crossing = (previous.X - current.X) * (point.Y - current.Y) / (previous.Y - current.Y) + current.X
			if point.X < crossing then
				inside = not inside
			end
		end
		previous = current
	end
	return inside
end

local function colorAt(x: number, y: number): Color3?
	local angle = math.atan2(x, -y) % FULL_TURN
	local step = FULL_TURN / Config.FaceSides
	local radius = math.cos(step / 2) / math.cos(angle % step - step / 2)
	if x * x + y * y > radius * radius then
		return nil
	end
	if insideMark(Vector2.new((x + 1) / 2, (y + 1) / 2)) then
		return Config.MarkColor
	end
	for _, sector in Config.Sectors do
		if angle / FULL_TURN < sector.Until then
			local color = sector.Color
			if x * x + y * y >= (radius * Config.RimFraction) ^ 2 then
				return Color3.new(color.R * Config.RimShade, color.G * Config.RimShade, color.B * Config.RimShade)
			end
			return color
		end
	end
	return Config.Sectors[#Config.Sectors].Color
end

local function strip(parent: Instance, x: number, row: number, width: number, color: Color3): ()
	local unit = Config.CanvasSize / Config.Rows
	local frame = Instance.new("Frame")
	frame.Name = "Sector"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromOffset(x * unit, row * unit)
	frame.Size = UDim2.fromOffset(width * unit, unit)
	frame.Parent = parent
end

local function drawSectors(surface: SurfaceGui): ()
	-- Merge each scanline into color runs. Build once, with no images, uploads or per-frame redraw.
	-- Only the left half changes in the source; the original right half and clock rim stay visible.
	local half = Config.Rows / 2
	for row = 0, Config.Rows - 1 do
		local start = 0
		local previous: Color3? = nil
		for column = 0, half do
			local color = if column < half
				then colorAt((column + 0.5 - half) / half, (row + 0.5 - half) / half)
				else nil
			if color == previous then
				continue
			end
			if previous then
				strip(surface, start, row, column - start, previous)
			end
			start, previous = column, color
		end
	end
end

local function roundedMark(
	parent: Instance,
	name: string,
	position: Vector2,
	size: Vector2,
	color: Color3,
	rotation: number
): ()
	local mark = Instance.new("Frame")
	mark.Name = name
	mark.AnchorPoint = Vector2.one / 2
	mark.Position = UDim2.fromScale(position.X, position.Y)
	mark.Size = UDim2.fromScale(size.X, size.Y)
	mark.Rotation = rotation
	mark.BackgroundColor3 = color
	mark.BorderSizePixel = 0
	mark.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mark
	mark.Parent = parent
end

function OvenDial.new(hand: BasePart, body: BasePart): (BasePart, SurfaceGui)
	local scale = body.Size.Z / Config.ReferenceBodyWidth
	local axis = hand.CFrame.RightVector
	local up = body.CFrame.UpVector
	local center = hand:GetPivot().Position
		+ up * Config.CenterHeight * scale
		+ axis * (Config.FaceDepth - Config.SurfaceLift + Config.SupportDepth / 2) * scale
	local part = Instance.new("Part")
	part.Name = "ReadyDial"
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(Config.Radius * 2, Config.Radius * 2, Config.SupportDepth) * scale
	-- Back faces the aisle; its canvas X axis matches the clock's clockwise sweep.
	part.CFrame = CFrame.fromMatrix(center, axis:Cross(up), up, -axis)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "BurnScale"
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.one * Config.CanvasSize
	surface.AlwaysOnTop = false
	surface.LightInfluence = 0
	surface.Enabled = false
	surface.Active = false
	surface.Parent = part
	drawSectors(surface)
	for _, degrees in Config.TickAngles do
		local angle = math.rad(degrees)
		local position = Vector2.one / 2 + Vector2.new(math.sin(angle), -math.cos(angle)) * Config.TickRadius / 2
		roundedMark(surface, "Tick", position, Config.TickSize, Config.TickColor, degrees)
	end
	part.Parent = body
	return part, surface
end

return OvenDial
