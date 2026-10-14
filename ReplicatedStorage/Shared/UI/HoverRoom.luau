--!strict
-- How far a hovered control may grow before it covers what is drawn around it.
--
-- Layout containers are invisible, so the walk climbs through them to the background the control is
-- drawn on: a drawn or clipping ancestor, or a drawn sibling behind it (along each axis it spans). Everything visible beside
-- the control on the way keeps half of the gap between them, so two neighbours growing and
-- shrinking at the same time never touch.

--[[ Tables ]]--
local HoverRoom = {}

--[[ Private Functions ]]--
local function draws(object: GuiObject): boolean
	if object.BackgroundTransparency < 1 then
		return true
	end
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		return object.Image ~= "" and object.ImageTransparency < 1
	end
	return false
end

--[[ Handling ]]--
--- The largest scale up to `limit` at which `element` grows about `pivot` (a share of its size) without
--- leaving its background or reaching past half of any gap. `drawnScale` is the scale the element
--- is drawn at right now, relative to rest, so a mid-animation call still measures the rest size.
function HoverRoom.Fit(element: GuiObject, limit: number, pivot: Vector2, drawnScale: number?): number
	local scale = drawnScale or 1
	if element.AbsoluteSize.X <= 0 or element.AbsoluteSize.Y <= 0 or scale <= 0 then
		return 1
	end
	local size: Vector2 = element.AbsoluteSize / scale
	local origin: Vector2 = element.AbsolutePosition + element.AbsoluteSize * pivot
	local min: Vector2 = origin - size * pivot
	local max: Vector2 = min + size
	local left, top, right, bottom = math.huge, math.huge, math.huge, math.huge
	-- Bounds the growth on each axis where `area` spans the control; returns whether it spans both.
	local function keepInside(area: GuiObject, spannedOnly: boolean): boolean
		local areaMin: Vector2 = area.AbsolutePosition
		local areaMax: Vector2 = areaMin + area.AbsoluteSize
		local spansX = areaMin.X <= min.X and areaMax.X >= max.X
		local spansY = areaMin.Y <= min.Y and areaMax.Y >= max.Y
		if spansX or not spannedOnly then
			left = math.min(left, min.X - areaMin.X)
			right = math.min(right, areaMax.X - max.X)
		end
		if spansY or not spannedOnly then
			top = math.min(top, min.Y - areaMin.Y)
			bottom = math.min(bottom, areaMax.Y - max.Y)
		end
		return spansX and spansY
	end

	local current: Instance = element
	local parent = element.Parent
	while parent and parent:IsA("GuiObject") do
		local onBackground = false
		for _, sibling in parent:GetChildren() do
			if sibling == current or not sibling:IsA("GuiObject") or not sibling.Visible then
				continue
			end
			local otherMin: Vector2 = sibling.AbsolutePosition
			local otherMax: Vector2 = otherMin + sibling.AbsoluteSize
			local gapX = math.max(otherMin.X - max.X, min.X - otherMax.X)
			local gapY = math.max(otherMin.Y - max.Y, min.Y - otherMax.Y)
			if gapX < 0 and gapY < 0 then
				-- A drawn sibling under its centre is its background; a control overhanging a ribbon
				-- still keeps to the ribbon's length. Art that only touches an edge is a neighbour.
				local centre = (min + max) / 2
				local under = centre.X >= otherMin.X and centre.X <= otherMax.X and centre.Y >= otherMin.Y and centre.Y <= otherMax.Y
				if under and draws(sibling) and keepInside(sibling, true) then
					onBackground = true
				end
			elseif gapX >= gapY then
				if otherMin.X >= max.X then
					right = math.min(right, gapX / 2)
				else
					left = math.min(left, gapX / 2)
				end
			elseif otherMin.Y >= max.Y then
				bottom = math.min(bottom, gapY / 2)
			else
				top = math.min(top, gapY / 2)
			end
		end
		if draws(parent) or parent.ClipsDescendants then
			keepInside(parent, false)
			onBackground = true
		end
		if onBackground then
			break
		end
		current = parent
		parent = parent.Parent
	end

	-- Each side grows by its share of the pivot.
	local fit = limit
	local function cap(room: number, share: number, length: number): ()
		if share > 0 then
			fit = math.min(fit, 1 + room / (share * length))
		end
	end
	cap(left, pivot.X, size.X)
	cap(right, 1 - pivot.X, size.X)
	cap(top, pivot.Y, size.Y)
	cap(bottom, 1 - pivot.Y, size.Y)
	return math.max(1, fit)
end

return HoverRoom
