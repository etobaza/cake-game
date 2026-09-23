--!strict
-- Screen geometry shared by focus and card placement. Projection clips edges at the camera near plane.

--[[ Services ]]
--
local GuiService = game:GetService("GuiService")

--[[ Tables ]]
--
local Geometry = {}
local Signs = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}
local Edges = {
	{ 1, 2 },
	{ 1, 3 },
	{ 1, 5 },
	{ 2, 4 },
	{ 2, 6 },
	{ 3, 4 },
	{ 3, 7 },
	{ 4, 8 },
	{ 5, 6 },
	{ 5, 7 },
	{ 6, 8 },
	{
		7,
		8,
	},
}

export type Rect = { min: Vector2, max: Vector2 }

--[[ Private Functions ]]
--
local function billboardOrigin(billboard: BillboardGui): Vector2?
	local camera = workspace.CurrentCamera
	local adornee = billboard.Adornee or billboard.Parent
	if not camera or not adornee then
		return nil
	end
	local point: Vector3
	if adornee:IsA("Attachment") then
		point = adornee.WorldPosition
	elseif adornee:IsA("BasePart") then
		point = adornee.Position
	else
		return nil
	end
	if billboard.MaxDistance > 0 and (point - camera.CFrame.Position).Magnitude > billboard.MaxDistance then
		return nil
	end
	point += billboard.StudsOffsetWorldSpace + camera.CFrame:VectorToWorldSpace(billboard.StudsOffset)
	local projected = camera:WorldToViewportPoint(point)
	if projected.Z <= 0 then
		return nil
	end
	local offset = Vector2.new(billboard.SizeOffset.X, -billboard.SizeOffset.Y)
	return Vector2.new(projected.X, projected.Y) + (offset - Vector2.one / 2) * billboard.AbsoluteSize
end

local function clipAncestor(
	rect: Rect,
	current: Instance,
	element: GuiObject,
	billboard: BillboardGui?,
	inset: Vector2
): Rect?
	if current == element then
		return rect
	end
	if current:IsA("GuiObject") and current.ClipsDescendants then
		return Geometry.Intersect(
			rect,
			{ min = current.AbsolutePosition + inset, max = current.AbsolutePosition + inset + current.AbsoluteSize }
		)
	end
	if billboard and current == billboard and billboard.ClipsDescendants then
		return Geometry.Intersect(rect, { min = inset, max = inset + billboard.AbsoluteSize })
	end
	return rect
end

--[[ Handling ]]
--
-- FullscreenExtension can shift the overlay's origin on notched/device-emulated
-- screens. Projected viewport points must be converted before assigning offsets.
function Geometry.ToScreen(screen: ScreenGui, point: Vector2): UDim2
	local inset = GuiService:GetGuiInset()
	local localPoint = point - screen.AbsolutePosition - inset
	return UDim2.fromOffset(localPoint.X, localPoint.Y)
end

function Geometry.Intersect(a: Rect, b: Rect): Rect?
	local low = Vector2.new(math.max(a.min.X, b.min.X), math.max(a.min.Y, b.min.Y))
	local high = Vector2.new(math.min(a.max.X, b.max.X), math.min(a.max.Y, b.max.Y))
	return if high.X - low.X > 2 and high.Y - low.Y > 2 then { min = low, max = high } else nil
end

function Geometry.Gui(element: GuiObject, viewport: Vector2): Rect?
	if not element:IsDescendantOf(game) or element.AbsoluteSize.X <= 0 or element.AbsoluteSize.Y <= 0 then
		return nil
	end
	-- AbsolutePosition uses the core GUI origin, even for ScreenInsets.None.
	-- WorldToViewportPoint and our overlay offsets use the full viewport origin.
	local billboard = element:FindFirstAncestorWhichIsA("BillboardGui")
	local inset: Vector2? = if billboard then billboardOrigin(billboard) else GuiService:GetGuiInset()
	if not inset then
		return nil
	end
	local rotation = math.rad(element.AbsoluteRotation)
	local originalSize = element.AbsoluteSize
	local center = element.AbsolutePosition + inset + originalSize / 2
	local size = Vector2.new(
		math.abs(math.cos(rotation)) * originalSize.X + math.abs(math.sin(rotation)) * originalSize.Y,
		math.abs(math.sin(rotation)) * originalSize.X + math.abs(math.cos(rotation)) * originalSize.Y
	)
	local rect: Rect? = { min = center - size / 2, max = center + size / 2 }
	local current: Instance? = element
	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return nil
			end
			if current:IsA("CanvasGroup") and current.GroupTransparency >= 0.99 then
				return nil
			end
		elseif current:IsA("LayerCollector") then
			if not current.Enabled then
				return nil
			end
		end
		if rect then
			rect = clipAncestor(rect, current, element, billboard, inset)
		end
		if not rect then
			return nil
		end
		current = current.Parent
	end
	return if rect then Geometry.Intersect(rect, { min = Vector2.zero, max = viewport }) else nil
end

function Geometry.Union(a: Rect?, b: Rect?): Rect?
	if not a then
		return b
	end
	if not b then
		return a
	end
	return {
		min = Vector2.new(math.min(a.min.X, b.min.X), math.min(a.min.Y, b.min.Y)),
		max = Vector2.new(math.max(a.max.X, b.max.X), math.max(a.max.Y, b.max.Y)),
	}
end

function Geometry.Box(camera: Camera, frame: CFrame, size: Vector3): Rect?
	local points: { Vector3 } = {}
	local projected: { Vector3 } = {}
	local near = math.max(0.05, -camera.NearPlaneZ)
	for index, sign in Signs do
		local world = frame:PointToWorldSpace(sign * size / 2)
		points[index] = camera.CFrame:PointToObjectSpace(world)
		if -points[index].Z >= near then
			projected[#projected + 1] = world
		end
	end
	for _, edge in Edges do
		local a, b = points[edge[1]], points[edge[2]]
		if (-a.Z >= near) == (-b.Z >= near) then
			continue
		end
		local alpha = (-near - a.Z) / (b.Z - a.Z)
		projected[#projected + 1] = camera.CFrame:PointToWorldSpace(a:Lerp(b, alpha))
	end
	local low, high = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, world in projected do
		local point = camera:WorldToViewportPoint(world)
		low = Vector2.new(math.min(low.X, point.X), math.min(low.Y, point.Y))
		high = Vector2.new(math.max(high.X, point.X), math.max(high.Y, point.Y))
	end
	return if #projected > 0 then { min = low, max = high } else nil
end

function Geometry.Area(rect: Rect?): number
	return if rect then (rect.max.X - rect.min.X) * (rect.max.Y - rect.min.Y) else 0
end

function Geometry.Safe(viewport: Vector2, padding: number): Rect
	local first, last = GuiService:GetGuiInset()
	local minimum = first + Vector2.one * padding
	local maximum = viewport - last - Vector2.one * padding
	return { min = minimum, max = Vector2.new(math.max(minimum.X + 1, maximum.X), math.max(minimum.Y + 1, maximum.Y)) }
end

function Geometry.Clamp(point: Vector2, rect: Rect): Vector2
	return Vector2.new(math.clamp(point.X, rect.min.X, rect.max.X), math.clamp(point.Y, rect.min.Y, rect.max.Y))
end

function Geometry.Rotate(vector: Vector2, degrees: number): Vector2
	local angle = math.rad(degrees)
	return Vector2.new(
		vector.X * math.cos(angle) - vector.Y * math.sin(angle),
		vector.X * math.sin(angle) + vector.Y * math.cos(angle)
	)
end

function Geometry.Angle(direction: Vector2): number
	return if direction.Magnitude < 1 then 0 else math.deg(math.atan2(direction.Y, direction.X)) + 90
end

function Geometry.Turn(current: number, target: number, alpha: number): number
	return current + ((target - current + 180) % 360 - 180) * math.clamp(alpha, 0, 1)
end

-- Project in viewport coordinates, including a stable edge direction behind the camera.
function Geometry.Project(camera: Camera, point: Vector3, safe: Rect): (Vector2, boolean, Vector2)
	local projected = camera:WorldToViewportPoint(point)
	local xy = Vector2.new(projected.X, projected.Y)
	local center = (safe.min + safe.max) / 2
	local onScreen = projected.Z > 0
		and xy.X >= safe.min.X
		and xy.X <= safe.max.X
		and xy.Y >= safe.min.Y
		and xy.Y <= safe.max.Y
	local relative = camera.CFrame:PointToObjectSpace(point)
	local direction = if relative.Z < -0.01 then xy - center else Vector2.new(relative.X, math.max(1, relative.Z * 0.5))
	if direction.Magnitude < 0.01 then
		direction = Vector2.new(0, -1)
	end
	if onScreen then
		return xy, true, direction
	end
	local extent = (safe.max - safe.min) / 2
	local distance =
		math.min(extent.X / math.max(0.001, math.abs(direction.X)), extent.Y / math.max(0.001, math.abs(direction.Y)))
	return center + direction * distance, false, direction
end

return Geometry
