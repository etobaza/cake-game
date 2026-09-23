--!strict
-- Reusable client guidance. Highest eligible priority wins; owners retain their pending hints.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Geometry = require(script.Parent.HintGeometry)
local HintBeam = require(script.Parent.HintBeam)
local Ripple = require(ReplicatedStorage.Shared.Libs.Ripple)
local Surface = require(script.Parent.HintSurface)

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
type Resolved = { rect: Geometry.Rect?, point: Vector3?, instance: Instance? }
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
		Pose: Ripple.Motion<number>,
		PosePhase: number,
		PoseElapsed: number,
		PoseDuration: number,
		Rotation: number?,
		Sequence: number,
		ResolverFailed: boolean,
		LastOcclusion: number,
		Connection: RBXScriptConnection?,
	},
	Hint
))
local Views: { [View]: boolean } = {}
local Sequence = 0
local Bound = false
local BINDING = "CakeHintPresentation"

local function hideSurface(self: View): ()
	self.Surface.Focus.Visible = false
	self.Surface.Finger.Visible = false
	self.Beam:Hide()
	self.Visible, self.OnScreen, self.Occluded, self.Bounds = false, false, false, nil
end

local function resolve(self: View): Resolved?
	local target = self.Target
	if typeof(target) == "function" then
		local ok, value = pcall(target)
		if not ok then
			if not self.ResolverFailed then
				warn(`[Hint] Target resolver failed: {value}`)
			end
			self.ResolverFailed = true
			return nil
		end
		self.ResolverFailed = false
		target = value
	end
	local camera = workspace.CurrentCamera
	if not target or not camera then
		return nil
	end
	if self.Mode == "Gui" then
		if typeof(target) ~= "Instance" or not target:IsA("GuiObject") then
			return nil
		end
		local rect = Geometry.Gui(target, camera.ViewportSize)
		return if rect then { rect = rect } else nil
	end
	if typeof(target) == "Vector3" then
		return { point = target }
	end
	if typeof(target) ~= "Instance" or not target:IsDescendantOf(workspace) then
		return nil
	end
	if target:IsA("BasePart") then
		return { point = target.Position, instance = target } :: Resolved
	end
	if target:IsA("Attachment") then
		return { point = target.WorldPosition, instance = target.Parent }
	end
	if target:IsA("Model") then
		return { point = target:GetPivot().Position, instance = target } :: Resolved
	end
	return nil
end

local function obstructed(point: Vector3, target: Instance?, camera: Camera): boolean
	local excluded: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(excluded, character)
	end
	local direction = point - camera.CFrame.Position
	if direction.Magnitude < 0.1 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	for _ = 1, 4 do
		params.FilterDescendantsInstances = excluded
		local hit = workspace:Raycast(camera.CFrame.Position, direction, params)
		if not hit or (hit.Position - point).Magnitude < 2 then
			return false
		end
		if target and (hit.Instance == target or hit.Instance:IsDescendantOf(target)) then
			return false
		end
		if hit.Instance.Transparency < 0.8 then
			return true
		end
		table.insert(excluded, hit.Instance)
	end
	return false
end

-- Manually stepped alongside rendering: hidden hints pause, and no extra loop owns opacity.
local function animatePose(self: View, delta: number): number
	local remaining = math.min(delta, 0.1)
	while remaining > 0 do
		if self.PoseDuration == 0 then
			local phase = Config.FingerPhases[self.PosePhase]
			self.PoseDuration = math.max(0.4, self.Options.FingerPeriod or Config.FingerPeriod) * phase.Fraction
			self.Pose:tween(phase.Pose, { duration = self.PoseDuration, easing = "quintInOut" })
		end
		local elapsed = math.min(remaining, self.PoseDuration - self.PoseElapsed)
		self.Pose:step(elapsed)
		self.PoseElapsed += elapsed
		remaining -= elapsed
		if self.PoseElapsed >= self.PoseDuration then
			self.PosePhase = self.PosePhase % #Config.FingerPhases + 1
			self.PoseElapsed, self.PoseDuration = 0, 0
		end
	end
	return math.clamp(self.Pose:getPosition(), 0, 1)
end

local function draw(self: View, resolved: Resolved, delta: number): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local surface, options = self.Surface, self.Options
	local viewport = camera.ViewportSize
	local safe = Geometry.Safe(viewport, Config.EdgePadding)
	local side = math.clamp(
		(
			options.FingerSize
			or math.clamp(
				Config.FingerSize * viewport.Y / Config.ReferenceHeight,
				Config.MinFingerSize,
				Config.FingerSize
			)
		) * (options.Scale or 1),
		24,
		math.max(24, math.min(viewport.X, viewport.Y) * 0.25)
	)
	local point: Vector2
	local desired = 0
	local onScreen = true
	local rect = resolved.rect
	self.Age += math.min(delta, 0.1)
	local progress = 1 - (1 - math.clamp(self.Age / Config.FocusDuration, 0, 1)) ^ 3
	if rect then
		self.Beam:Hide()
		local anchor = options.TargetPoint or Vector2.new(0.5, 0.5)
		point = rect.min + (rect.max - rect.min) * anchor
		-- Continuous diagonal placement gives the hand room without discrete side flips.
		local relative = point - (safe.min + safe.max) / 2
		desired = math.clamp(relative.X / math.max(1, (safe.max.X - safe.min.X) / 2) * 65, -65, 65)
		if point.Y > safe.max.Y - side then
			desired = 180 - desired
		end
		local pad = Vector2.one * math.max(0, options.Padding or Config.Padding)
		self.Bounds = Geometry.Intersect({ min = rect.min - pad, max = rect.max + pad }, safe)
		local bounds = self.Bounds or rect
		local minimum = safe.min:Lerp(bounds.min, progress)
		local maximum = safe.max:Lerp(bounds.max, progress)
		surface.Focus.Position = Geometry.ToScreen(surface.Screen, minimum)
		surface.Focus.Size = UDim2.fromOffset(maximum.X - minimum.X, maximum.Y - minimum.Y)
		surface.Shade.Thickness = math.max(viewport.X, viewport.Y) * 2
		surface.Shade.Transparency = 1 - progress * (1 - Config.ShadeTransparency)
		surface.Focus.Visible = options.Dim ~= false
	else
		local worldPoint = (resolved.point :: Vector3) + (options.WorldOffset or Vector3.zero)
		local margin = Vector2.one * side
		local markerSafe = { min = safe.min + margin, max = safe.max - margin }
		markerSafe.max = Vector2.new(
			math.max(markerSafe.min.X + 1, markerSafe.max.X),
			math.max(markerSafe.min.Y + 1, markerSafe.max.Y)
		)
		local direction: Vector2
		point, onScreen, direction = Geometry.Project(camera, worldPoint, markerSafe)
		local character = Players.LocalPlayer.Character
		local root = character and character.PrimaryPart
		if onScreen and root then
			local origin = camera:WorldToViewportPoint(root.Position)
			if origin.Z > 0 then
				direction = point - Vector2.new(origin.X, origin.Y)
			end
		end
		desired = Geometry.Angle(direction)
		if options.Occlusion ~= false and os.clock() - self.LastOcclusion >= Config.OcclusionInterval then
			self.LastOcclusion = os.clock()
			self.Occluded = obstructed(worldPoint, resolved.instance, camera)
		end
		if options.Beam ~= false then
			self.Beam:Show(worldPoint)
		else
			self.Beam:Hide()
		end
		self.Bounds = { min = point, max = point }
		surface.Focus.Visible = false
	end
	if options.Rotation then
		desired = options.Rotation
	end
	self.Rotation = if self.Rotation
		then Geometry.Turn(self.Rotation, desired, 1 - math.exp(-Config.RotationSpeed * delta))
		else desired
	local rotation = self.Rotation :: number
	local offset = Geometry.Rotate((Config.FingerTip - Vector2.one / 2) * side, rotation)
	local center = point - offset
	-- Keep the entire rotated square inside the safe viewport; the target stays live.
	local radians = math.rad(rotation)
	local half = side * (math.abs(math.cos(radians)) + math.abs(math.sin(radians))) / 2
	local fingerSafe = { min = safe.min + Vector2.one * half, max = safe.max - Vector2.one * half }
	fingerSafe.max =
		Vector2.new(math.max(fingerSafe.min.X, fingerSafe.max.X), math.max(fingerSafe.min.Y, fingerSafe.max.Y))
	center = Geometry.Clamp(center, fingerSafe)
	surface.Finger.Position = Geometry.ToScreen(surface.Screen, center)
	surface.Finger.Size = UDim2.fromOffset(side, side)
	surface.Finger.Rotation = rotation % 360
	local pose = animatePose(self, delta)
	-- Smooth overlap keeps the shared hand silhouette readable without hard alpha clamps.
	surface.Straight.ImageTransparency = 1 - progress * (1 - pose * pose)
	surface.Bent.ImageTransparency = 1 - progress * (1 - (1 - pose) * (1 - pose))
	surface.Finger.Visible = true
	self.Visible, self.OnScreen = true, onScreen
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
	self.Pose:setPosition(0)
	self.PosePhase, self.PoseElapsed, self.PoseDuration = 1, 0, 0
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
		Pose = Ripple.createMotion(0),
		PosePhase = 1,
		PoseElapsed = 0,
		PoseDuration = 0,
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
		RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + 3, step)
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
	self.Pose:destroy()
	self.Beam:Destroy()
	if not next(Views) and Bound then
		RunService:UnbindFromRenderStep(BINDING)
		Bound = false
	end
end

return Hint
