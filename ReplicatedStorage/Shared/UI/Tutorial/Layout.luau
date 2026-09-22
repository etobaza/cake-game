--!strict
-- Chooses a dock from screen edges and HUD gaps. Model bounds never position the card.
-- Presenter retains this placement across camera motion, prompts and hint expansion.

--[[ Services ]]--
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

--[[ Modules ]]--
local Geometry = require(script.Parent.Geometry)

--[[ Tables ]]--
local Layout = {}

type Obstacle = { rect: Geometry.Rect, weight: number }

--[[ Private Functions ]]--
local function rectangle(center: Vector2, size: Vector2): Geometry.Rect
	return { min = center - size / 2, max = center + size / 2 }
end

local function obstacles(viewport: Vector2, objects: { GuiObject }): { Obstacle }
	local result = {}
	for _, object in objects do
		-- The optional quest meter yields its portrait HUD area to the active lesson.
		if viewport.X < 600 and object.Name == "Quests" then
			continue
		end
		local rect = Geometry.Gui(object, viewport)
		if not rect or Geometry.Area(rect) >= viewport.X * viewport.Y * 0.4 then
			continue
		end
		local control = object.Name == "Run" or object.Name == "JumpButton"
		result[#result + 1] = { rect = rect, weight = if control then 1000 else 8 }
	end
	if UserInputService.TouchEnabled then
		local height = math.min(190, viewport.Y * 0.38)
		result[#result + 1] = {
			rect = {
				min = Vector2.new(0, viewport.Y - height),
				max = Vector2.new(math.min(185, viewport.X * 0.4), viewport.Y),
			},
			weight = 1000,
		}
		result[#result + 1] = {
			rect = {
				min = Vector2.new(viewport.X - math.min(175, viewport.X * 0.36), viewport.Y - height),
				max = viewport,
			},
			weight = 1000,
		}
	end
	return result
end

-- Resolve authored controls at the scenario refresh rate; moving bounds stay live each frame.
function Layout.Collect(hud: Instance): { GuiObject }
	local result = {}
	for _, name in { "Time", "Order", "Hotbar", "Currency", "SideBtns", "Quests", "Controls" } do
		local object = hud:FindFirstChild(name)
		if object and object:IsA("GuiObject") then
			result[#result + 1] = object
		end
	end
	local controls = hud:FindFirstChild("Controls")
	for _, object in (if controls then controls:GetChildren() else {}) :: { Instance } do
		if object:IsA("GuiObject") then
			result[#result + 1] = object
		end
	end
	if UserInputService.TouchEnabled then
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local touch = playerGui and playerGui:FindFirstChild("TouchGui")
		for _, object in if touch then touch:GetDescendants() else {} do
			-- The dynamic stick's invisible drag canvas spans half the screen. Its visible
			-- control is covered by the reserved lower-left area above.
			if object.Name ~= "JumpButton" then
				continue
			end
			if object:IsA("GuiObject") then
				result[#result + 1] = object
			end
		end
	end
	return result
end

--[[ Handling ]]--
function Layout.Safe(viewport: Vector2): Geometry.Rect
	local topLeft, bottomRight = GuiService:GetGuiInset()
	return { min = topLeft + Vector2.new(12, 12), max = viewport - bottomRight - Vector2.new(12, 12) }
end

-- Size is the reserved expanded footprint, including when the card is folded or shows less text.
-- Protected bounds belong to an actionable GUI or prompt; the model's outline is not an obstacle.
function Layout.Place(
	viewport: Vector2,
	size: Vector2,
	objects: { GuiObject },
	protected: Geometry.Rect?,
	previous: Vector2?
): Vector2
	local safe = Layout.Safe(viewport)
	local minimum = safe.min + size / 2
	local maximum =
		Vector2.new(math.max(minimum.X, safe.max.X - size.X / 2), math.max(minimum.Y, safe.max.Y - size.Y / 2))
	local preferred = Vector2.new(maximum.X, minimum.Y + 56)
	if viewport.X < 600 and UserInputService.TouchEnabled then
		preferred = Vector2.new(maximum.X, viewport.Y - math.min(190, viewport.Y * 0.38) - size.Y / 2 - 8)
	end
	if previous then
		preferred = previous + size / 2
	end
	local candidates = { preferred, minimum, maximum, Vector2.new(minimum.X, maximum.Y) }
	local occupied = obstacles(viewport, objects)
	if protected then
		occupied[#occupied + 1] = { rect = protected, weight = 1000 }
	end
	occupied[#occupied + 1] = {
		rect = { min = Vector2.new(safe.max.X - 44, safe.min.Y), max = Vector2.new(safe.max.X, safe.min.Y + 44) },
		weight = 1000,
	}
	-- Portrait docks stay on an edge. A short landscape screen also has a usable
	-- central strip between the two thumb controls, below the clock and above the hand.
	local short = viewport.Y < 420
	local columns: { number } = if short then { minimum.X, maximum.X, viewport.X / 2 } else { minimum.X, maximum.X }
	for _, obstacle in occupied do
		local area = obstacle.rect
		for _, x in columns do
			candidates[#candidates + 1] = Vector2.new(x, area.max.Y + size.Y / 2 + 8)
			candidates[#candidates + 1] = Vector2.new(x, area.min.Y - size.Y / 2 - 8)
		end
	end
	local best, score = preferred, math.huge
	for _, candidate in candidates do
		local center =
			Vector2.new(math.clamp(candidate.X, minimum.X, maximum.X), math.clamp(candidate.Y, minimum.Y, maximum.Y))
		local rect = rectangle(center, size)
		local value = (center - preferred).Magnitude
		for _, area in occupied do
			local overlap = Geometry.Area(Geometry.Intersect(rect, area.rect))
			value += overlap * area.weight
		end
		if value < score then
			best, score = center, value
		end
	end
	return best - size / 2
end

return Layout
