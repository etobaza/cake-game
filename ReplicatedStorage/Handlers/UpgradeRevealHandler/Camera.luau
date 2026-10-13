--!strict
-- Finds an interior-safe view and validates every movement segment, including the return.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RevealConfig = require(ReplicatedStorage.Shared.Configs.UpgradeReveal)
local Config = RevealConfig.Camera
local Target = require(script.Parent.Target)
type CameraObject = typeof(Instance.new("Camera"))
type Framing = { Horizontal: number, Top: number, Bottom: number, Pitch: number }
local CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

local Camera = {}
Camera.__index = Camera
export type Camera = typeof(setmetatable(
	{} :: {
		Object: CameraObject,
		Character: Model?,
		Subject: Instance?,
		Type: Enum.CameraType,
		Home: CFrame,
		Focus: CFrame,
		Fov: number,
		Start: CFrame,
		Finish: CFrame,
		Last: CFrame,
		Params: RaycastParams,
		Overlap: OverlapParams,
		TargetPosition: Vector3,
		TargetSize: Vector3,
		Framing: Framing,
		Direct: boolean,
	},
	Camera
))

local function clear(position: Vector3, overlap: OverlapParams): boolean
	return #workspace:GetPartBoundsInRadius(position, Config.Radius, overlap) == 0
end

local function segment(from: Vector3, to: Vector3, params: RaycastParams): boolean
	local delta = to - from
	return delta.Magnitude < 1e-3 or workspace:Spherecast(from, Config.Radius, delta, params) == nil
end

local function screenFraming(camera: CameraObject): Framing
	local viewport = camera.ViewportSize
	local card = RevealConfig.Card
	local density = math.clamp(viewport.Y / 900, 0.85, 1.2)
	local width = math.min(card.Width * density, viewport.X - card.Margin * 2)
	local height = if width < 400 then card.NarrowHeight else math.max(card.MinHeight, card.Height * density)
	local bottom =
		math.clamp((viewport.Y - height - card.Bottom * density) / math.max(viewport.Y, 1) - Config.CardGap, 0.35, 0.9)
	local center = (Config.ScreenMargin + bottom) / 2
	local tangent = math.tan(math.rad(Config.FieldOfView / 2))
	return {
		Horizontal = tangent * math.max(viewport.X / math.max(viewport.Y, 1), 0.3) * (1 - 2 * Config.ScreenMargin),
		Top = tangent * (1 - 2 * Config.ScreenMargin),
		Bottom = tangent * (2 * bottom - 1),
		Pitch = -math.atan((1 - 2 * center) * tangent),
	}
end

local function view(position: Vector3, center: Vector3, fit: Framing): CFrame
	return CFrame.lookAt(position, center) * CFrame.Angles(fit.Pitch, 0, 0)
end

-- Solve all four frustum planes for the eight world-aligned bounds corners, including depth.
local function requiredDistance(size: Vector3, direction: Vector3, fit: Framing): number
	local frame = view(direction, Vector3.zero, fit)
	local axis = frame:VectorToObjectSpace(direction)
	local distance = Config.MinDistance
	for _, corner in CORNERS do
		local point = frame:VectorToObjectSpace(size * corner / 2)
		distance = math.max(
			distance,
			(point.X + point.Z * fit.Horizontal) / (axis.X + axis.Z * fit.Horizontal),
			(-point.X + point.Z * fit.Horizontal) / (-axis.X + axis.Z * fit.Horizontal),
			(point.Y + point.Z * fit.Top) / (axis.Y + axis.Z * fit.Top),
			(-point.Y + point.Z * fit.Bottom) / (-axis.Y + axis.Z * fit.Bottom),
			(point.Z + Config.Radius) / axis.Z
		)
	end
	return distance
end

local function fits(frame: CFrame, center: Vector3, size: Vector3, fit: Framing): boolean
	for _, corner in CORNERS do
		local point = frame:PointToObjectSpace(center + size * corner / 2)
		local depth = -point.Z
		if
			depth <= Config.Radius
			or math.abs(point.X) > depth * fit.Horizontal
			or point.Y > depth * fit.Top
			or -point.Y > depth * fit.Bottom
		then
			return false
		end
	end
	return true
end

local function framing(
	target: Target.Target,
	camera: CameraObject,
	params: RaycastParams,
	overlap: OverlapParams
): CFrame?
	local center = target.Frame.Position
	local fit = screenFraming(camera)
	local best: CFrame? = nil
	local bestScore = -math.huge
	for _, angle in Config.Angles do
		for _, elevation in Config.Elevations do
			local direction = target.Frame:VectorToWorldSpace(
				CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(Vector3.new(0, elevation, 1).Unit)
			)
			local minimum = requiredDistance(target.Size, direction, fit)
			local distance = math.min(minimum * Config.FramePadding, Config.MaxDistance)
			local hit = workspace:Spherecast(center, Config.Radius, direction * distance, params)
			local available = if hit then math.max(0, hit.Distance - Config.WallMargin) else distance
			if available < minimum then
				continue
			end
			local position = center + direction * available
			if not clear(position, overlap) then
				continue
			end
			local score = available / distance - math.abs(angle) / 180 * 0.12 - elevation * 0.08
			if score > bestScore then
				bestScore = score
				best = view(position, center, fit)
			end
		end
	end
	return best
end

function Camera.new(target: Target.Target): Camera?
	local object = workspace.CurrentCamera
	if not object or object.CameraType == Enum.CameraType.Scriptable then
		return nil
	end
	local ignored: { Instance } = table.clone(target.Roots)
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(ignored, character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignored
	overlap.RespectCanCollide = true
	local finish = framing(target, object, params, overlap)
	if not finish then
		return nil
	end
	local self = setmetatable({
		Object = object,
		Character = character,
		Subject = object.CameraSubject,
		Type = object.CameraType,
		Home = object.CFrame,
		Focus = object.Focus,
		Fov = object.FieldOfView,
		Start = object.CFrame,
		Finish = finish,
		Last = object.CFrame,
		Params = params,
		Overlap = overlap,
		TargetPosition = target.Frame.Position,
		TargetSize = target.Size,
		Framing = screenFraming(object),
		Direct = clear(object.CFrame.Position, overlap) and segment(object.CFrame.Position, finish.Position, params),
	}, Camera)
	object.CameraType = Enum.CameraType.Scriptable
	return self
end

function Camera.Owned(self: Camera): boolean
	return workspace.CurrentCamera == self.Object
		and self.Object.CameraType == Enum.CameraType.Scriptable
		and self.Object.CFrame == self.Last
end

function Camera.Write(self: Camera, frame: CFrame): boolean
	if not self:Owned() then
		return false
	end
	self.Object.CFrame = frame
	self.Object.Focus = CFrame.new(self.TargetPosition)
	self.Last = frame
	return true
end

function Camera.Approach(self: Camera, alpha: number): number
	self.Object.FieldOfView = self.Fov + (Config.FieldOfView - self.Fov) * alpha
	if self.Direct then
		local frame = self.Home:Lerp(self.Finish, alpha)
		if clear(frame.Position, self.Overlap) and segment(self.Last.Position, frame.Position, self.Params) then
			self:Write(frame)
			return 0
		end
		self.Direct = false
	end
	-- A brief veil covers a cut between rooms. No interpolation can cross a wall or roof.
	if alpha >= 0.5 then
		self:Write(self.Finish)
	end
	return math.sin(math.pi * alpha)
end

function Camera.Orbit(self: Camera, alpha: number): ()
	local offset = self.Finish.Position - self.TargetPosition
	local rotated = CFrame.Angles(0, math.rad(Config.OrbitDegrees) * alpha, 0):VectorToWorldSpace(offset)
	local position = self.TargetPosition + rotated
	local frame = view(position, self.TargetPosition, self.Framing)
	if
		clear(position, self.Overlap)
		and fits(frame, self.TargetPosition, self.TargetSize, self.Framing)
		and segment(self.Last.Position, position, self.Params)
		and segment(self.TargetPosition, position, self.Params)
	then
		self:Write(frame)
	end
end

function Camera.BeginReturn(self: Camera): ()
	self.Start = self.Last
	self.Direct = clear(self.Home.Position, self.Overlap)
		and segment(self.Start.Position, self.Home.Position, self.Params)
end

function Camera.Return(self: Camera, alpha: number): number
	self.Object.FieldOfView = Config.FieldOfView + (self.Fov - Config.FieldOfView) * alpha
	if self.Direct then
		local frame = self.Start:Lerp(self.Home, alpha)
		if clear(frame.Position, self.Overlap) and segment(self.Last.Position, frame.Position, self.Params) then
			self:Write(frame)
			return 0
		end
		self.Direct = false
	end
	if alpha >= 0.5 then
		self:Write(self.Home)
	end
	return math.sin(math.pi * alpha)
end

function Camera.Destroy(self: Camera): ()
	if not self:Owned() then
		return
	end
	local object = self.Object
	local sameCharacter = Players.LocalPlayer.Character == self.Character
	if sameCharacter then
		object.CFrame = self.Home
		object.Focus = self.Focus
	end
	local subject = self.Subject
	object.CameraSubject = if sameCharacter
			and subject
			and subject.Parent
		then subject
		else (Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
	object.FieldOfView = self.Fov
	object.CameraType = if sameCharacter then self.Type else Enum.CameraType.Custom
end

return Camera
