--!strict
-- One guest body: an avatar rig that walks to a spot, sits down and walks back out.
-- Orders and patience are presented by the owner's HUD, without overhead UI.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local CollisionConfig = require(_Configs.Collision)
local GuestsConfig = require(_Configs.Guests)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local DisplayCustomers = require(ReplicatedStorage.Shared.Configs.DisplayCustomers)
local CharacterAnimations = require(ReplicatedStorage.Shared.Configs.CharacterAnimations)
local TickHandler = require(ServerScriptService.Handlers.TickHandler)

--[[ Constants ]]--
local ARRIVE_DISTANCE = 1
local HORIZONTAL = Vector3.new(1, 0, 1)
local TURN_RATE = math.rad(GuestsConfig.TurnRate)
-- Shorter flat vectors give no usable direction; the current heading is kept instead.
local MIN_DIRECTION_LENGTH = 0.05
-- Within 10 degrees of the chair's facing, the seat tween no longer swings the body round.
local SEAT_FACING_DOT = math.cos(math.rad(10))
-- Animation names as this file calls them; the ids behind them live in the guest config.
local IDLE = "Idle"
local WALK = "Walk"
local SIT = "Sit"

--[[ Tables ]]--
local Guest = {}
Guest.__index = Guest

type Route = {
	Points: { Vector3 },
	-- The point ending the current leg, which starts at the previous point or, first, at Origin.
	Index: number,
	Origin: Vector3,
	LookAt: Vector3?,
	OnArrive: (() -> ())?,
	Deadline: number,
}
type Seating = {
	Seat: Seat,
	Deadline: number,
	NextTryAt: number,
	OnSeated: () -> (),
	OnFailed: () -> (),
	-- Captured once the body has turned to the seat and the sit begins.
	StartFrame: CFrame?,
	Lift: number,
	Adjusted: boolean,
}

export type Guest = typeof(setmetatable(
	{} :: {
		Janitor: any,
		Model: Model,
		Humanoid: Humanoid,
		Root: BasePart,
		Facing: AlignOrientation,
		Tracks: { [string]: AnimationTrack },
		Playing: string?,
		Route: Route?,
		RouteRevision: number,
		-- Flat unit direction of travel; the body turns towards it at a human pace.
		Heading: Vector3,
		Speed: number,
		-- Pace cap from the street crowd, so a pedestrian keeps its gap to the one ahead.
		SpeedLimit: number,
		-- Where a guest who has arrived turns to face.
		LookDirection: Vector3?,
		Seating: Seating?,
		StandingUntil: number?,
		ApproachFrame: CFrame?,
		ExitAt: number?,
		FadeEndsAt: number?,
		Destroyed: boolean,
		OnBlocked: (() -> ())?,
	},
	Guest
))

--[[ Private Functions ]]--
-- The rig comes straight from the avatar service, so it has no Animate script of its own: without
-- these tracks a guest slides across the room in a T-pose.
local function LoadTracks(humanoid: Humanoid): { [string]: AnimationTrack }
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local ids = {
		[IDLE] = GuestsConfig.Avatar.IdleAnimation,
		[WALK] = GuestsConfig.Avatar.WalkAnimation,
		[SIT] = GuestsConfig.Avatar.SitAnimation,
	}

	local tracks = {}
	for name, id in ids do
		local animation = Instance.new("Animation")
		animation.AnimationId = id

		tracks[name] = animator:LoadAnimation(animation)
		animation:Destroy()
	end

	return tracks
end

-- Humanoid.AutoRotate snaps to every new heading; a physical constraint turns the body smoothly.
local function CreateFacing(root: BasePart): AlignOrientation
	local attachment = Instance.new("Attachment")
	attachment.Name = "FacingAttachment"
	attachment.Parent = root

	local facing = Instance.new("AlignOrientation")
	facing.Name = "Facing"
	facing.Mode = Enum.OrientationAlignmentMode.OneAttachment
	facing.Attachment0 = attachment
	facing.MaxTorque = math.huge
	facing.Responsiveness = GuestsConfig.TurnResponsiveness
	facing.CFrame = root.CFrame.Rotation
	facing.Parent = root

	return facing
end

-- Closest point to `position` on the leg from `from` to `to`; all three lie on the ground plane.
local function ClosestOnLeg(position: Vector3, from: Vector3, to: Vector3): Vector3
	local leg = to - from
	local lengthSquared = leg:Dot(leg)
	if lengthSquared == 0 then
		return from
	end

	return from + leg * math.clamp((position - from):Dot(leg) / lengthSquared, 0, 1)
end

-- Rotates a flat unit vector about the vertical axis towards another, by at most `maxAngle` radians.
local function TurnTowards(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local side = if from:Cross(to).Y < 0 then -1 else 1

	return CFrame.Angles(0, side * maxAngle, 0):VectorToWorldSpace(from)
end

local function LegStart(route: Route): Vector3
	return (if route.Index == 1 then route.Origin else route.Points[route.Index - 1]) * HORIZONTAL
end

-- Moves past corners at their bisector: the look-ahead starts each turn early, so the body never
-- touches the corner itself. Returns whether the body has reached the final point.
local function Advance(route: Route, position: Vector3, now: number): boolean
	local points = route.Points
	while route.Index < #points do
		local corner = points[route.Index] * HORIZONTAL
		local after = points[route.Index + 1] * HORIZONTAL
		local current = (ClosestOnLeg(position, LegStart(route), corner) - position).Magnitude
		local following = (ClosestOnLeg(position, corner, after) - position).Magnitude
		if following > current then
			break
		end
		route.Index += 1
		route.Deadline = now + GuestsConfig.WalkTimeout
	end
	local final = points[#points]

	return not final or (route.Index == #points and (final * HORIZONTAL - position).Magnitude < ARRIVE_DISTANCE)
end

-- The point LookAhead studs further along the route than the body's place on its current leg.
local function LookAheadPoint(route: Route, position: Vector3): Vector3
	local points = route.Points
	local cursor = ClosestOnLeg(position, LegStart(route), points[route.Index] * HORIZONTAL)
	local budget = GuestsConfig.LookAhead
	for index = route.Index, #points do
		local point = points[index] * HORIZONTAL
		local length = (point - cursor).Magnitude
		if length >= budget then
			return cursor + (point - cursor) * (budget / length)
		end
		budget -= length
		cursor = point
	end

	return cursor
end

-- Studs left to walk: straight to the end of the current leg, then along the remaining legs.
local function RemainingDistance(route: Route, position: Vector3): number
	local points = route.Points
	local distance = (points[route.Index] * HORIZONTAL - position).Magnitude
	for index = route.Index + 1, #points do
		distance += ((points[index] - points[index - 1]) * HORIZONTAL).Magnitude
	end

	return distance
end

--[[ Handling ]]--
function Guest.new(customerId: string, name: string, rig: Model, position: Vector3, parent: Instance): Guest?
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = rig:FindFirstChild("Head") :: BasePart?
	if not humanoid or not root or not head then
		rig:Destroy()
		return nil
	end

	local self = setmetatable({}, Guest) :: Guest

	self.Janitor = Janitor.new()
	self.Destroyed = false
	self.RouteRevision = 0
	self.Model = rig
	self.Humanoid = humanoid
	self.Root = root

	rig.Name = customerId
	humanoid.DisplayName = name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.AutoRotate = false

	for _, piece in rig:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.CollisionGroup = CollisionConfig.Groups.Guest
		end
	end

	-- Moved by the root, not by the pivot: a rig without a primary part pivots around its bounding box.
	root.CFrame = CFrame.new(position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
	self.Facing = CreateFacing(root)
	self.Heading = root.CFrame.LookVector
	self.Speed = 0
	self.SpeedLimit = GuestsConfig.WalkSpeed
	rig.Parent = parent

	-- Server owned: a guest walking under a client's control would be one more thing to trust.
	root:SetNetworkOwner(nil)

	self.Tracks = LoadTracks(humanoid)
	self:Play(IDLE)

	self.Janitor:Add(rig, "Destroy")
	for _, track in self.Tracks do
		self.Janitor:Add(track, "Destroy")
	end
	self.Janitor:Add(
		TickHandler.Tick:Connect(function(deltaTime: number)
			self:Update(os.clock(), deltaTime)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		rig.Destroying:Connect(function()
			self:Destroy()
		end),
		"Disconnect"
	)

	return self
end

-- One looping animation at a time: the rig has no state machine of its own.
function Guest.Play(self: Guest, name: string): ()
	if self.Playing == name then
		return
	end

	local fade = GuestsConfig.Avatar.AnimationFadeTime
	for trackName, track in self.Tracks do
		if trackName ~= name then
			track:Stop(fade)
		end
	end

	self.Tracks[name]:Play(fade)
	self.Playing = name
end

-- The shared tick owns progress, so cancelling a route leaves no waiter behind. With a lookAt the
-- guest eases to a stop and turns to face it; without one the walk keeps its pace, so a route
-- started from the arrival callback carries on without a stop.
function Guest.WalkRoute(self: Guest, points: { Vector3 }, lookAt: Vector3?, onArrive: (() -> ())?): ()
	if self.Destroyed then
		return
	end
	self.Janitor:Remove("SeatMotion")
	self.Seating = nil
	self.StandingUntil = nil
	self.LookDirection = nil
	local now = os.clock()
	self.RouteRevision += 1
	self.Route = {
		Points = points,
		Index = 1,
		Origin = self.Root.Position,
		LookAt = lookAt,
		OnArrive = onArrive,
		Deadline = now + GuestsConfig.WalkTimeout,
	}
	local seat = self.Humanoid.SeatPart
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if seat and weld and weld:IsA("Weld") and weld.Part1 == self.Root and self.ApproachFrame then
		-- Return to the walkable approach before releasing physics; detaching over the chair
		-- lets Humanoid's standing-height correction kick the body upwards in one frame.
		self.StandingUntil = now + GuestsConfig.SeatTransitionSeconds
		local tween = TweenService:Create(weld, TweenInfo.new(GuestsConfig.SeatTransitionSeconds), {
			C0 = seat.CFrame:ToObjectSpace(self.ApproachFrame) * weld.C1,
		})
		self.Janitor:Add(tween, "Cancel", "SeatMotion")
		self:Play(IDLE)
		tween:Play()
		return
	end
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	self.Humanoid.Sit = false
	if not self.Facing.Enabled then
		self:ResumeFacing()
	end
end

function Guest.Exit(self: Guest, points: { Vector3 }, timeout: number?, fade: boolean?): ()
	self.ExitAt = os.clock() + (timeout or GuestsConfig.ExitTimeout)
	self:WalkRoute(points, nil, function()
		if fade then
			self:FadeOut()
		else
			self:Destroy()
		end
	end)
end

-- Retire at the street boundary, with a short fade instead of an abrupt disappearance.
function Guest.FadeOut(self: Guest): ()
	if self.Destroyed or self.FadeEndsAt then
		return
	end
	-- A fading body stops navigating; Update brakes it out of its last stride.
	self.Route = nil
	self.ExitAt = nil
	self.FadeEndsAt = os.clock() + GuestsConfig.Street.FadeSeconds
	self.Model:SetAttribute("VisitorState", "Fading")
	for _, part in self.Model:GetDescendants() do
		if not part:IsA("BasePart") and not part:IsA("Decal") and not part:IsA("Texture") then
			continue
		end
		local tween = TweenService:Create(part, TweenInfo.new(GuestsConfig.Street.FadeSeconds), { Transparency = 1 })
		self.Janitor:Add(tween, "Cancel")
		tween:Play()
	end
end

function Guest.CarryTakeaway(self: Guest): ()
	if self.Destroyed or self.Model:FindFirstChild("Takeaway") then
		return
	end
	local hand = self.Model:FindFirstChild("RightHand") or self.Model:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local box = Instance.new("Part")
	box.Name = "Takeaway"
	box.Size = DisplayCustomers.PackageSize
	box.Color = DisplayCustomers.PackageColor
	box.Material = Enum.Material.SmoothPlastic
	box.CanCollide = false
	box.CanTouch = false
	box.CanQuery = false
	box.Massless = true
	box.CFrame = hand.CFrame * DisplayCustomers.PackageHandOffset
	box.Parent = self.Model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = box
	weld.Parent = box
	self.Janitor:Add(box, "Destroy")
end

function Guest.PetCat(self: Guest): ()
	if self.Destroyed then
		return
	end
	local animator = self.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = CharacterAnimations.Clips.PetCat.Id
	local track = animator:LoadAnimation(animation)
	animation:Destroy()
	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = false
	self.Janitor:Add(track, "Destroy", "PetCat")
	track:Play(CharacterAnimations.FadeTime)
end

-- A carrier distinguishes adoption from a pastry takeaway and leaves with the guest.
function Guest.CarryCat(self: Guest): ()
	if self.Destroyed or self.Model:FindFirstChild("CatCarrier") then
		return
	end
	local hand = self.Model:FindFirstChild("RightHand")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local carrier = Instance.new("Model")
	carrier.Name = "CatCarrier"
	carrier.Parent = self.Model
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3): ()
		local part = Instance.new("Part")
		part.Name, part.Size, part.Color = name, size, color
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		part.Massless = true
		part.CFrame = hand.CFrame * offset
		part.Parent = carrier
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = hand, part, part
	end
	local teal = Color3.fromRGB(77, 185, 181)
	piece("Basket", Vector3.new(1.3, 0.8, 1), CFrame.new(0, -0.7, 0), teal)
	piece("Door", Vector3.new(0.95, 0.57, 0.04), CFrame.new(0, -0.68, -0.52), Color3.fromRGB(40, 63, 66))
	for i = -2, 2 do
		piece("Bar", Vector3.new(0.04, 0.57, 0.05), CFrame.new(i * 0.17, -0.68, -0.55), Color3.fromRGB(223, 237, 220))
	end
	self.Janitor:Add(carrier, "Destroy", "CatCarrier")
end

function Guest.Update(self: Guest, now: number, deltaTime: number): ()
	if self.Destroyed then
		return
	end
	local fadedOut = self.FadeEndsAt ~= nil and now >= self.FadeEndsAt
	if not self.Model.Parent or fadedOut or (self.ExitAt and now >= self.ExitAt) then
		self:Destroy()
		return
	end
	if self.StandingUntil then
		if now < self.StandingUntil and self.Humanoid.SeatPart then
			return
		end
		self:StandUp(now)
	end
	if self.Seating then
		self:UpdateSeating(now, deltaTime)
		return
	end
	local route = self.Route
	if not route then
		-- Brake out of the last stride and finish turning towards the spot; a seat holds its own pose.
		if not self.Humanoid.SeatPart then
			self:Steer(self.LookDirection, 0, deltaTime)
		end
		return
	end
	local position = self.Root.Position * HORIZONTAL
	if Advance(route, position, now) then
		self:Arrive(route)
		return
	end
	-- Failed routes retire in place; moving a stuck body through walls hides navigation defects.
	if now >= route.Deadline then
		self.Route = nil
		local onBlocked = self.OnBlocked
		self.OnBlocked = nil
		if onBlocked then
			onBlocked()
		end
		if not self.Destroyed then
			self:FadeOut()
		end
		return
	end
	local offset = LookAheadPoint(route, position) - position
	local direction = if offset.Magnitude > MIN_DIRECTION_LENGTH then offset.Unit else self.Heading
	-- Facing away from the path holds the pace down, so a guest turns before striding off.
	local speed = self.SpeedLimit * math.max(self.Heading:Dot(direction), 0)
	if route.LookAt then
		speed = math.min(speed, self.SpeedLimit * RemainingDistance(route, position) / GuestsConfig.SlowdownDistance)
	end
	self:Steer(direction, speed, deltaTime)
end

function Guest.Arrive(self: Guest, route: Route): ()
	self.Route = nil
	local revision = self.RouteRevision
	-- A porch callback can continue directly into the cafe; the next route keeps heading and pace.
	if route.OnArrive then
		route.OnArrive()
	end
	local lookAt = route.LookAt
	local seated = self.Seating ~= nil or self.Humanoid.SeatPart ~= nil
	if not lookAt or self.Destroyed or seated or self.RouteRevision ~= revision then
		return
	end
	local offset = (lookAt - self.Root.Position) * HORIZONTAL
	if offset.Magnitude >= ARRIVE_DISTANCE then
		self.LookDirection = offset.Unit
	end
end

-- Turns the heading at the configured rate and eases the pace towards `targetSpeed`.
function Guest.Steer(self: Guest, direction: Vector3?, targetSpeed: number, deltaTime: number): ()
	if direction then
		self.Heading = TurnTowards(self.Heading, direction, TURN_RATE * deltaTime)
		self.Facing.CFrame = CFrame.lookAt(Vector3.zero, self.Heading)
	end
	self.Speed = math.clamp(
		targetSpeed,
		self.Speed - GuestsConfig.Deceleration * deltaTime,
		self.Speed + GuestsConfig.Acceleration * deltaTime
	)
	self.Humanoid.WalkSpeed = self.Speed
	self.Humanoid:Move(if self.Speed > 0 then self.Heading else Vector3.zero)

	local moving = self.Speed > GuestsConfig.Avatar.MovingThreshold
	self:Play(if moving then WALK else IDLE)
	if moving then
		self.Tracks[WALK]:AdjustSpeed(self.Speed / GuestsConfig.Avatar.WalkReferenceSpeed)
	end
end

-- Releases the seat once the weld has carried the body back to its approach.
function Guest.StandUp(self: Guest, now: number): ()
	self.StandingUntil = nil
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	self.Humanoid.Sit = false
	self.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	self.Root.AssemblyLinearVelocity = Vector3.zero
	self.Root.AssemblyAngularVelocity = Vector3.zero
	self:ResumeFacing()
	local route = self.Route
	if route then
		route.Origin = self.Root.Position
		route.Deadline = now + GuestsConfig.WalkTimeout
	end
end

-- Hands orientation back to the heading, starting from where the body faces now.
function Guest.ResumeFacing(self: Guest): ()
	local look = self.Root.CFrame.LookVector * HORIZONTAL
	if look.Magnitude > MIN_DIRECTION_LENGTH then
		self.Heading = look.Unit
	end
	self.Facing.CFrame = CFrame.lookAt(Vector3.zero, self.Heading)
	self.Facing.Enabled = true
end

-- Seat:Sit may be refused during cooldown or by another occupant. Confirm physics before the HUD.
function Guest.SitOn(self: Guest, seat: Seat, onSeated: () -> (), onFailed: () -> ()): ()
	self.Janitor:Remove("SeatMotion")
	self.StandingUntil = nil
	local torso = self.Model:FindFirstChild("LowerTorso")
	local lift = self.Root.Size.Y / 2
	if torso and torso:IsA("BasePart") then
		local rootAttachment = self.Root:FindFirstChild("RootRigAttachment")
		local torsoAttachment = torso:FindFirstChild("RootRigAttachment")
		if
			rootAttachment
			and rootAttachment:IsA("Attachment")
			and torsoAttachment
			and torsoAttachment:IsA("Attachment")
		then
			-- Rest attachments work for Motor6D and AnimationConstraint rigs. Reading the live
			-- torso offset here would bake the current walking bob into the seated height.
			local offset = rootAttachment.CFrame * torsoAttachment.CFrame:Inverse()
			lift = -offset.Position.Y + torso.Size.Y / 2
		end
	end
	self.Seating = {
		Seat = seat,
		Deadline = os.clock() + GuestsConfig.SeatTimeout,
		NextTryAt = 0,
		OnSeated = onSeated,
		OnFailed = onFailed,
		StartFrame = nil,
		Lift = lift + seat.Size.Y / 2,
		Adjusted = false,
	}
end

-- Turns to the table before sitting, so the seat tween lowers the body instead of spinning it.
-- Returns the pose the sit starts from once the body faces the seat.
function Guest.FaceSeat(self: Guest, pending: Seating, now: number, deltaTime: number): CFrame?
	local seat = pending.Seat
	local facing = seat.CFrame.LookVector * HORIZONTAL
	local look = self.Root.CFrame.LookVector * HORIZONTAL
	local turning = facing.Magnitude > MIN_DIRECTION_LENGTH and look.Unit:Dot(facing.Unit) < SEAT_FACING_DOT
	if turning and seat.Parent and now < pending.Deadline then
		self:Steer(facing.Unit, 0, deltaTime)
		return nil
	end
	-- The weld owns the pose from here. Sitting follows in this frame, so a touch cannot seat the
	-- body with Roblox's default weld pose first.
	self.Speed = 0
	self.Humanoid.WalkSpeed = 0
	self.Humanoid:Move(Vector3.zero)
	self.Root.AssemblyLinearVelocity = Vector3.zero
	self.Root.AssemblyAngularVelocity = Vector3.zero
	self.Facing.Enabled = false
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
	self.ApproachFrame = self.Root.CFrame
	pending.StartFrame = self.Root.CFrame

	return self.Root.CFrame
end

function Guest.UpdateSeating(self: Guest, now: number, deltaTime: number): ()
	local pending = self.Seating
	if not pending then
		return
	end
	local seat = pending.Seat
	local startFrame = pending.StartFrame or self:FaceSeat(pending, now, deltaTime)
	if not startFrame then
		return
	end
	local weld = seat:FindFirstChild("SeatWeld")
	if not pending.Adjusted and weld and weld:IsA("Weld") and weld.Part1 == self.Root then
		pending.Adjusted = true
		self:Play(SIT)
		-- Roblox's fixed seat offset floats scaled avatars. Fit the pelvis to the cushion,
		-- and interpolate the weld from the approach pose so seating does not teleport.
		weld.C0 = seat.CFrame:ToObjectSpace(startFrame) * weld.C1
		local tween =
			TweenService:Create(weld, TweenInfo.new(GuestsConfig.SeatTransitionSeconds, Enum.EasingStyle.Quad), {
				C0 = CFrame.new(0, pending.Lift, 0) * weld.C1,
			})
		self.Janitor:Add(tween, "Cancel", "SeatMotion")
		tween:Play()
	end
	if seat.Parent and seat.Occupant == self.Humanoid and self.Humanoid.SeatPart == seat then
		self.Seating = nil
		self:Play(SIT)
		pending.OnSeated()
		return
	end
	if not seat.Parent or now >= pending.Deadline then
		self.Seating = nil
		self:ResumeFacing()
		pending.OnFailed()
		return
	end
	if now >= pending.NextTryAt and not seat.Occupant then
		seat:Sit(self.Humanoid)
		pending.NextTryAt = now + GuestsConfig.MoveRefreshSeconds
		-- SeatWeld is normally created synchronously; set its starting pose before physics.
		if seat:FindFirstChild("SeatWeld") then
			self:UpdateSeating(now, deltaTime)
		end
	end
end

function Guest.Destroy(self: Guest): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Route = nil
	self.Seating = nil
	self.StandingUntil = nil
	self.Janitor:Destroy()
end

return Guest
