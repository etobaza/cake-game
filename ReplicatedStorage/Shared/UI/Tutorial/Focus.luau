--!strict
-- A single focus owner. The presenter supplies the frame callback; this class creates no loop.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Animate = require(script.Parent.Parent.Animate)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local Geometry = require(script.Parent.Geometry)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Layout = require(script.Parent.Layout)
local Prompt = require(ReplicatedStorage.Handlers.PromptHandler)
local Targets = require(script.Parent.Targets)
local Types = require(ReplicatedStorage.Shared.GameTypes)

--[[ Types ]]--
-- The authored StarterGui.Tutorial children the focus overlay draws with.
type AuthoredScreen = ScreenGui & { Hole: GuiObject, Outline: GuiObject, Direction: GuiObject }

--[[ Tables ]]--
local Focus = {}
Focus.__index = Focus

--[[ Private Functions ]]--
local function visiblePart(part: Instance): boolean
	return part:IsA("BasePart") and part.Transparency < 0.98 and part.LocalTransparencyModifier < 0.98
end

local function cacheParts(self: any, model: Instance?): ()
	if self.PartSource == model then
		return
	end
	self.PartsJanitor:Cleanup()
	self.PartSource = model
	self.Parts = if model then model:GetDescendants() else {}
	if model and model:IsA("BasePart") then
		self.Parts[#self.Parts + 1] = model
	end
	if not model then
		return
	end
	self.PartsJanitor:Add(
		model.DescendantAdded:Connect(function(object: Instance): ()
			if object:IsA("BasePart") then
				self.Parts[#self.Parts + 1] = object
			end
		end),
		"Disconnect"
	)
end

local function project(self: any, target: Targets.Target, camera: Camera): (Geometry.Rect?, Vector3)
	if target.frame and target.size then
		return Geometry.Box(camera, target.frame, target.size), target.frame.Position
	end
	local rect: Geometry.Rect? = nil
	local sum, count = Vector3.zero, 0
	for _, object in self.Parts do
		if not object.Parent or not visiblePart(object) then
			continue
		end
		local part = object :: BasePart
		rect = Geometry.Union(rect, Geometry.Box(camera, part.CFrame, part.Size))
		sum += part.Position
		count += 1
	end
	local part = target.part :: BasePart
	if count == 0 then
		return Geometry.Box(camera, part.CFrame, part.Size), part.Position
	end
	return rect, sum / count
end

local function unobstructed(camera: Camera, target: Targets.Target, point: Vector3): boolean
	local excluded: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		excluded[#excluded + 1] = character
	end
	local origin = camera.CFrame.Position
	local direction = point - origin
	if direction.Magnitude < 0.1 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	for _ = 1, 6 do
		params.FilterDescendantsInstances = excluded
		local hit = workspace:Raycast(origin, direction, params)
		if not hit then
			return true
		end
		if hit.Instance == target.model or (target.model and hit.Instance:IsDescendantOf(target.model)) then
			return true
		end
		if (hit.Position - point).Magnitude < 1.8 then
			return true
		end
		if hit.Instance.Transparency < 0.8 then
			return false
		end
		excluded[#excluded + 1] = hit.Instance
	end
	return false
end

local function promptRect(target: Targets.Target, viewport: Vector2): Geometry.Rect?
	local prompt, billboard, root = Prompt:GetActiveView()
	if not prompt or prompt.Parent ~= target.part or not billboard or not billboard.Enabled or not root then
		return nil
	end
	return Geometry.Gui(root, viewport)
end

-- Keep the fingertip on the target, choosing the side with room for the whole hand.
local function pointCursor(self: any, rect: Geometry.Rect, viewport: Vector2): ()
	local cursor = self.Cursor
	if not cursor then
		return
	end
	local tuning = Config.Focus.Cursor
	local safe = Layout.Safe(viewport)
	local clipped = Geometry.Intersect(rect, safe)
	if not clipped then
		return
	end
	local size = math.clamp(math.min(viewport.X, viewport.Y) * tuning.ViewportScale, tuning.MinSize, tuning.MaxSize)
	local half = Vector2.one * size / 2
	local low, high = safe.min + half, safe.max - half
	local center = (clipped.min + clipped.max) / 2
	local inset = Vector2.new(
		math.min(tuning.TargetInset, (clipped.max.X - clipped.min.X) / 2),
		math.min(tuning.TargetInset, (clipped.max.Y - clipped.min.Y) / 2)
	)
	local offset = (tuning.Tip - Vector2.one / 2) * size
	local candidates = {
		{ tip = Vector2.new(center.X, clipped.max.Y - inset.Y), offset = offset, rotation = 0 },
		{ tip = Vector2.new(center.X, clipped.min.Y + inset.Y), offset = -offset, rotation = 180 },
		{
			tip = Vector2.new(clipped.max.X - inset.X, center.Y),
			offset = Vector2.new(offset.Y, -offset.X),
			rotation = -90,
		},
		{
			tip = Vector2.new(clipped.min.X + inset.X, center.Y),
			offset = Vector2.new(-offset.Y, offset.X),
			rotation = 90,
		},
	}
	local bestPosition, bestRotation, bestCost = center, 0, math.huge
	for _, candidate in candidates do
		local position = candidate.tip - candidate.offset
		local fitted = Vector2.new(
			math.clamp(position.X, low.X, math.max(low.X, high.X)),
			math.clamp(position.Y, low.Y, math.max(low.Y, high.Y))
		)
		local cost = (fitted - position).Magnitude
		if cost >= bestCost then
			continue
		end
		bestPosition, bestRotation, bestCost = fitted, candidate.rotation, cost
		if cost == 0 then
			break
		end
	end
	cursor.Size = UDim2.fromOffset(size, size)
	cursor.Position = Geometry.ToScreen(self.Screen, bestPosition)
	cursor.Rotation = bestRotation
	cursor.Visible = true
end

local function pointArrow(self: any, camera: Camera, point: Vector3): ()
	local localPoint = camera.CFrame:PointToObjectSpace(point)
	local direction = Vector2.new(localPoint.X, -localPoint.Y)
	if localPoint.Z > 0 then
		direction = Vector2.new(localPoint.X, math.abs(localPoint.Z) * 0.5 + 1)
	end
	if direction.Magnitude < 0.01 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit
	local viewport = camera.ViewportSize
	local radius = Vector2.new(math.max(40, viewport.X / 2 - 90), math.max(40, viewport.Y / 2 - 100))
	local distance =
		math.min(radius.X / math.max(math.abs(direction.X), 0.001), radius.Y / math.max(math.abs(direction.Y), 0.001))
	local position = viewport / 2 + direction * distance
	self.Direction.Position = Geometry.ToScreen(self.Screen, position)
	self.Direction.Arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	local character = Players.LocalPlayer.Character
	local root = character and character.PrimaryPart
	self.Direction.Distance.Text = if root
		then tostring(math.floor((root.Position - point).Magnitude)) .. " studs"
		else "This way"
	self.Direction.Visible = true
	local arrow = Geometry.Gui(self.Direction.Arrow, viewport)
	if arrow then
		pointCursor(self, arrow, viewport)
	end
end

--[[ Handling ]]--
function Focus.new(screen: ScreenGui): Focus
	local authored = screen :: AuthoredScreen
	local self: any = setmetatable({
		Screen = screen,
		Janitor = Janitor.new(),
		Hole = authored.Hole,
		Outline = authored.Outline,
		Direction = authored.Direction,
		Key = "",
		GoalGui = nil,
	}, Focus)
	local cursor = screen:FindFirstChild("Cursor")
	self.Cursor = if cursor and cursor:IsA("ImageLabel") then cursor else nil
	if self.Cursor then
		self.Cursor.AnchorPoint = Vector2.one / 2
		self.Cursor.Active, self.Cursor.Selectable, self.Cursor.Visible = false, false, false
	else
		warn("[TutorialFocus] StarterGui.Tutorial.Cursor must be authored and saved")
	end
	screen.DisplayOrder = Config.Focus.DisplayOrder
	self.Hole.Mask.Thickness = Config.Focus.Thickness
	self.Hole.Corner.CornerRadius = UDim.new(0, Config.Focus.Corner)
	self.Outline.Corner.CornerRadius = UDim.new(0, Config.Focus.Corner)
	self.PartsJanitor = Janitor.new()
	self.Janitor:Add(self.PartsJanitor, "Destroy")
	self.PartSource = nil
	self.Parts = {}
	self.Fade = Animate.Track(self.Hole.Mask, "Transparency", 1, function(value: number): ()
		self.Hole.Mask.Transparency = value
	end)
	self.Janitor:Add(self.Fade, "destroy")
	return self
end

function Focus.Hide(self: Focus): ()
	self.Hole.Visible = false
	self.Outline.Visible = false
	self.Direction.Visible = false
	if self.Cursor then
		self.Cursor.Visible = false
	end
	self.GoalGui = nil
	self.PromptBounds = nil
end

-- Resolve at the scenario refresh rate. Frame updates only project the cached objects.
function Focus.Resolve(self: Focus, spec: Types.TutorialTarget?): ()
	self.Spec = spec
	local camera = workspace.CurrentCamera
	self.Target = if camera then Targets.Resolve(spec, camera.ViewportSize) else nil
	local target = self.Target
	cacheParts(self, if target then target.model or target.part else nil)
end

function Focus.Update(self: Focus): (Geometry.Rect?, string?)
	self:Hide()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local target, spec = self.Target, self.Spec
	if not target then
		return nil, nil
	end
	local rect: Geometry.Rect? = nil
	local transparency = Config.Focus.GuiTransparency
	if target.gui then
		rect = Geometry.Gui(target.gui, camera.ViewportSize)
		self.GoalGui = target.gui
	else
		local point: Vector3
		rect, point = project(self, target, camera)
		local projected = camera:WorldToViewportPoint(point)
		local clipped = rect and Geometry.Intersect(rect, { min = Vector2.zero, max = camera.ViewportSize })
		if not clipped or projected.Z <= 0 or not unobstructed(camera, target, point) then
			pointArrow(self, camera, point)
			return nil, "Follow the arrow to the object"
		end
		self.PromptBounds = promptRect(target, camera.ViewportSize)
		rect = Geometry.Union(clipped, self.PromptBounds)
		transparency = Config.Focus.WorldTransparency
	end
	if not rect then
		return nil, target.message
	end
	local key = if spec
		then spec.kind .. ":" .. spec.id .. ":" .. tostring(spec.seat) .. ":" .. tostring(target.gui)
		else ""
	if key ~= self.Key then
		self.Key = key
		self.Fade:setPosition(1)
	end
	self.Fade:spring(transparency, { frequency = 7, dampingRatio = 1 })
	local padding = Vector2.one * Config.Focus.Padding
	local center = (rect.min + rect.max) / 2
	local size = rect.max - rect.min + padding * 2
	for _, frame in { self.Hole, self.Outline } do
		frame.Position = Geometry.ToScreen(self.Screen, center)
		frame.Size = UDim2.fromOffset(size.X, size.Y)
		frame.Visible = true
	end
	-- A nearby actionable prompt is more precise than the object's combined focus bounds.
	pointCursor(self, self.PromptBounds or rect, camera.ViewportSize)
	return { min = rect.min - padding, max = rect.max + padding }, target.message
end

function Focus.Destroy(self: Focus): ()
	self:Hide()
	self.Janitor:Destroy()
end

export type Focus = typeof(setmetatable(
	{} :: {
		Screen: ScreenGui,
		Janitor: any,
		PartsJanitor: any,
		PartSource: Instance?,
		Parts: { Instance },
		Hole: any,
		Outline: any,
		Direction: any,
		Cursor: ImageLabel?,
		Fade: any,
		Key: string,
		GoalGui: GuiObject?,
		Target: Targets.Target?,
		Spec: Types.TutorialTarget?,
		PromptBounds: Geometry.Rect?,
	},
	Focus
))

return Focus
