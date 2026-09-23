--!strict
-- Reusable client guidance. Highest eligible priority wins; owners retain their pending hints.

--[[ Services ]]
--
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]
--
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Geometry = require(script.Parent.HintGeometry)
local HintAnimation = require(script.Parent.HintAnimation)
local HintBeam = require(script.Parent.HintBeam)
local Surface = require(script.Parent.HintSurface)

--[[ Types ]]
--
export type WorldTarget = BasePart | Model | Attachment | Vector3
export type GuiTarget = GuiObject | (() -> GuiObject?)
export type WorldResolver = WorldTarget | (() -> WorldTarget?)
export type Options = {
	Key: string?,
	Priority: number?,
	Duration: number?,
	Rotation: number?,
	FingerSize: number?,
	Scale: number?,
	FingerPeriod: number?,
	Padding: number?,
	Dim: boolean?,
	Beam: boolean?,
	TargetPoint: Vector2?,
	WorldOffset: Vector3?,
	Occlusion: boolean?,
}
type Target = GuiObject | WorldTarget
type WorldResolved = { kind: "World", point: Vector3, instance: Instance? }
type Resolved = { kind: "Gui", rect: Geometry.Rect } | WorldResolved
type Frame = { camera: Camera, viewport: Vector2, safe: Geometry.Rect, side: number, progress: number }

--[[ Constants ]]
--
local BINDING = "CakeHintPresentation"
local RENDER_PRIORITY_OFFSET = 3

--[[ Tables ]]
--
local Hint = {}
Hint.__index = Hint

export type View = typeof(setmetatable(
	{} :: {
		Surface: Surface.View,
		Beam: HintBeam.View,
		Defaults: Options,
		Options: Options,
		Target: GuiTarget | WorldResolver?,
		Mode: string?,
		Key: string?,
		Enabled: boolean,
		Closed: boolean,
		Visible: boolean,
		OnScreen: boolean,
		Occluded: boolean,
		Bounds: Geometry.Rect?,
		Since: number,
		Age: number,
		Animation: HintAnimation.Animation,
		Rotation: number?,
		Sequence: number,
		ResolverFailed: boolean,
		LastOcclusion: number,
		Connection: RBXScriptConnection?,
	},
	Hint
))

--[[ Private Variables ]]
--
local Views: { [View]: boolean } = {}
local Sequence = 0
local Bound = false

--[[ Private Functions ]]
--
local function hideSurface(self: View): ()
	self.Surface.Focus.Visible = false
	self.Surface.Finger.Visible = false
	self.Beam:Hide()

	self.Visible, self.OnScreen, self.Occluded, self.Bounds = false, false, false, nil
end

local function readTarget(self: View): Target?
	local target = self.Target
	if typeof(target) ~= "function" then
		return target
	end

	local ok, value = pcall(target)
	if ok then
		self.ResolverFailed = false
		return value
	end

	if not self.ResolverFailed then
		warn(`[Hint] Target resolver failed: {value}`)
	end

	self.ResolverFailed = true
	return nil
end

local function resolveGui(target: Target, viewport: Vector2): Resolved?
	if typeof(target) ~= "Instance" or not target:IsA("GuiObject") then
		return nil
	end

	local rect = Geometry.Gui(target, viewport)
	return if rect then { kind = "Gui", rect = rect } else nil
end

local function resolveWorld(target: Target): Resolved?
	if typeof(target) == "Vector3" then
		return { kind = "World", point = target, instance = nil }
	end

	if typeof(target) ~= "Instance" or not target:IsDescendantOf(workspace) then
		return nil
	end

	if target:IsA("BasePart") then
		local resolved: WorldResolved = { kind = "World", point = target.Position, instance = target }
		return resolved
	end

	if target:IsA("Attachment") then
		return { kind = "World", point = target.WorldPosition, instance = target.Parent }
	end

	if target:IsA("Model") then
		local resolved: WorldResolved = { kind = "World", point = target:GetPivot().Position, instance = target }
		return resolved
	end

	return nil
end

local function resolve(self: View): Resolved?
	local target = readTarget(self)
	local camera = workspace.CurrentCamera
	if not target or not camera then
		return nil
	end

	if self.Mode == "Gui" then
		return resolveGui(target, camera.ViewportSize)
	end

	return resolveWorld(target)
end

local function obstructed(point: Vector3, target: Instance?, camera: Camera): boolean
	local excluded: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(excluded, character)
	end

	local direction = point - camera.CFrame.Position
	if direction.Magnitude < Config.OcclusionMinRayLength then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	for _ = 1, Config.OcclusionMaxHits do
		params.FilterDescendantsInstances = excluded
		local hit = workspace:Raycast(camera.CFrame.Position, direction, params)
		if not hit or (hit.Position - point).Magnitude < Config.OcclusionTargetRadius then
			return false
		end

		if target and (hit.Instance == target or hit.Instance:IsDescendantOf(target)) then
			return false
		end

		if hit.Instance.Transparency < Config.OcclusionTransparency then
			return true
		end
		table.insert(excluded, hit.Instance)
	end

	return false
end

local function fingerSize(options: Options, viewport: Vector2): number
	local responsive =
		math.clamp(Config.FingerSize * viewport.Y / Config.ReferenceHeight, Config.MinFingerSize, Config.FingerSize)
	local requested = (options.FingerSize or responsive) * (options.Scale or 1)
	local maximum =
		math.max(Config.MinScaledFingerSize, math.min(viewport.X, viewport.Y) * Config.MaxFingerViewportFraction)

	return math.clamp(requested, Config.MinScaledFingerSize, maximum)
end

local function drawGui(self: View, rect: Geometry.Rect, frame: Frame): (Vector2, number)
	local surface, options = self.Surface, self.Options
	self.Beam:Hide()
	self.Occluded = false

	local anchor = options.TargetPoint or Vector2.one / 2
	local point = rect.min + (rect.max - rect.min) * anchor
	local relative = point - (frame.safe.min + frame.safe.max) / 2
	local halfWidth = math.max(1, (frame.safe.max.X - frame.safe.min.X) / 2)
	local rotation = math.clamp(relative.X / halfWidth, -1, 1) * Config.GuiMaxRotation

	-- Turn the hand inward near the bottom edge without discrete left/right flips.
	if point.Y > frame.safe.max.Y - frame.side then
		rotation = 180 - rotation
	end

	local padding = Vector2.one * math.max(0, options.Padding or Config.Padding)
	self.Bounds = Geometry.Intersect({ min = rect.min - padding, max = rect.max + padding }, frame.safe)

	local bounds = self.Bounds or rect
	local minimum = frame.safe.min:Lerp(bounds.min, frame.progress)
	local maximum = frame.safe.max:Lerp(bounds.max, frame.progress)
	surface.Focus.Position = Geometry.ToScreen(surface.Screen, minimum)
	surface.Focus.Size = UDim2.fromOffset(maximum.X - minimum.X, maximum.Y - minimum.Y)
	surface.Focus.Visible = options.Dim ~= false

	-- Twice the longest viewport edge covers the screen outside the focus hole.
	surface.Shade.Thickness = math.max(frame.viewport.X, frame.viewport.Y) * 2
	surface.Shade.Transparency = 1 - frame.progress * (1 - Config.ShadeTransparency)

	return point, rotation
end

local function playerDirection(camera: Camera, point: Vector2, fallback: Vector2, onScreen: boolean): Vector2
	local character = Players.LocalPlayer.Character
	local root = character and character.PrimaryPart
	if not onScreen or not root then
		return fallback
	end

	local origin = camera:WorldToViewportPoint(root.Position)
	if origin.Z <= 0 then
		return fallback
	end

	return point - Vector2.new(origin.X, origin.Y)
end

local function updateOcclusion(self: View, point: Vector3, target: Instance?, camera: Camera): ()
	if self.Options.Occlusion == false then
		self.Occluded = false
		return
	end

	local now = os.clock()
	if now - self.LastOcclusion < Config.OcclusionInterval then
		return
	end

	self.LastOcclusion = now
	self.Occluded = obstructed(point, target, camera)
end

local function drawWorld(self: View, point: Vector3, target: Instance?, frame: Frame): (Vector2, number, boolean)
	local worldPoint = point + (self.Options.WorldOffset or Vector3.zero)
	local markerSafe = Geometry.Inset(frame.safe, frame.side, 1)
	local projected, onScreen, direction = Geometry.Project(frame.camera, worldPoint, markerSafe)
	direction = playerDirection(frame.camera, projected, direction, onScreen)

	updateOcclusion(self, worldPoint, target, frame.camera)

	if self.Options.Beam == false then
		self.Beam:Hide()
	else
		self.Beam:Show(worldPoint)
	end

	self.Bounds = { min = projected, max = projected }
	self.Surface.Focus.Visible = false

	return projected, Geometry.Angle(direction), onScreen
end

local function drawFinger(self: View, point: Vector2, desired: number, frame: Frame, delta: number): ()
	local surface = self.Surface
	local targetRotation = self.Options.Rotation or desired
	local alpha = 1 - math.exp(-Config.RotationSpeed * delta)
	local rotation = if self.Rotation then Geometry.Turn(self.Rotation, targetRotation, alpha) else targetRotation
	self.Rotation = rotation

	local offset = Geometry.Rotate((Config.FingerTip - Vector2.one / 2) * frame.side, rotation)
	local radians = math.rad(rotation)
	local halfExtent = frame.side * (math.abs(math.cos(radians)) + math.abs(math.sin(radians))) / 2
	local fingerSafe = Geometry.Inset(frame.safe, halfExtent, 0)
	local center = Geometry.Clamp(point - offset, fingerSafe)

	surface.Finger.Position = Geometry.ToScreen(surface.Screen, center)
	surface.Finger.Size = UDim2.fromOffset(frame.side, frame.side)
	surface.Finger.Rotation = rotation % 360
	surface.Finger.Visible = true

	local pose = self.Animation:Step(delta, self.Options.FingerPeriod or Config.FingerPeriod)
	-- Quadratic overlap retains the shared hand silhouette throughout the crossfade.
	surface.Straight.ImageTransparency = 1 - frame.progress * (1 - pose * pose)
	surface.Bent.ImageTransparency = 1 - frame.progress * (1 - (1 - pose) * (1 - pose))
end

local function draw(self: View, resolved: Resolved, delta: number): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	self.Age += math.clamp(delta, 0, Config.MaxAnimationDelta)
	local elapsed = math.clamp(self.Age / Config.FocusDuration, 0, 1)
	local frame: Frame = {
		camera = camera,
		viewport = camera.ViewportSize,
		safe = Geometry.Safe(camera.ViewportSize, Config.EdgePadding),
		side = fingerSize(self.Options, camera.ViewportSize),
		-- Cubic ease-out for the focus opening.
		progress = 1 - (1 - elapsed) ^ 3,
	}

	local point: Vector2
	local rotation: number
	local onScreen = true

	if resolved.kind == "Gui" then
		point, rotation = drawGui(self, resolved.rect, frame)
	else
		point, rotation, onScreen = drawWorld(self, resolved.point, resolved.instance, frame)
	end

	drawFinger(self, point, rotation, frame, delta)
	self.Visible = true
	self.OnScreen = onScreen
end

local function step(delta: number): ()
	local winner: View? = nil
	local selected: Resolved? = nil

	for view in Views do
		local duration = view.Options.Duration
		if duration and duration > 0 and os.clock() - view.Since >= duration then
			view:Destroy()
			continue
		end

		if not view.Enabled or not view.Mode or GuiService.MenuIsOpen then
			continue
		end

		local target = resolve(view)
		if not target then
			continue
		end

		local priority = view.Options.Priority or Config.Priority
		local previous = if winner then winner.Options.Priority or Config.Priority else -math.huge
		if not winner or priority > previous or (priority == previous and view.Sequence > winner.Sequence) then
			winner, selected = view, target
		end
	end

	for view in Views do
		if not winner or view.Surface.Screen ~= winner.Surface.Screen then
			hideSurface(view)
		end
	end

	if winner and selected then
		draw(winner, selected, delta)
	end
end

local function set(self: View, mode: string, target: GuiTarget | WorldResolver, options: Options?): ()
	if self.Closed then
		return
	end

	local settings = table.clone(self.Defaults)
	if options then
		-- Options is a heterogeneous record; keep the dynamic key write local to merging.
		for key, value in options do
			(settings :: any)[key] = value
		end
	end

	local changed = self.Mode ~= mode
		or (if settings.Key then self.Key ~= settings.Key else self.Target ~= target or self.Key ~= nil)
	self.Target, self.Mode, self.Options, self.Key = target, mode, settings, settings.Key
	if not changed then
		return
	end

	Sequence += 1
	self.Sequence, self.Since, self.Age = Sequence, os.clock(), 0
	self.Animation:Reset()
	self.Rotation, self.ResolverFailed, self.LastOcclusion = nil, false, 0
	hideSurface(self)
end

function Hint.new(defaults: Options?): View
	assert(RunService:IsClient(), "[Hint] Create hints on the client")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local self = setmetatable({
		Surface = Surface.new(playerGui),
		Beam = HintBeam.new(),
		Defaults = table.clone(defaults or {}),
		Options = {},
		Enabled = true,
		Closed = false,
		Visible = false,
		OnScreen = false,
		Occluded = false,
		Since = os.clock(),
		Age = 0,
		Animation = HintAnimation.new(),
		Sequence = 0,
		ResolverFailed = false,
		LastOcclusion = 0,
	}, Hint) :: View

	Views[self] = true
	self.Connection = self.Surface.Screen.Destroying:Connect(function()
		self:Destroy()
	end)

	if not Bound then
		Bound = true
		RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + RENDER_PRIORITY_OFFSET, step)
	end

	return self
end

function Hint.Gui(self: View, target: GuiTarget, options: Options?): ()
	set(self, "Gui", target, options)
end

function Hint.World(self: View, target: WorldResolver, options: Options?): ()
	set(self, "World", target, options)
end

function Hint.GetBounds(self: View): Geometry.Rect?
	return self.Bounds
end

function Hint.IsOnScreen(self: View): boolean
	return self.Visible and self.OnScreen
end

function Hint.IsVisible(self: View): boolean
	return self.Visible
end

function Hint.SetEnabled(self: View, enabled: boolean): ()
	if self.Closed then
		return
	end

	self.Enabled = enabled
	if not enabled then
		hideSurface(self)
	end
end

function Hint.Hide(self: View): ()
	self.Mode, self.Target, self.Key = nil, nil, nil
	hideSurface(self)
end

function Hint.Destroy(self: View): ()
	if self.Closed then
		return
	end

	self.Closed = true
	Views[self] = nil
	self:Hide()
	self.Enabled = false

	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	self.Surface.Screen:Destroy()
	self.Animation:Destroy()
	self.Beam:Destroy()

	if not next(Views) and Bound then
		RunService:UnbindFromRenderStep(BINDING)
		Bound = false
	end
end

return Hint
