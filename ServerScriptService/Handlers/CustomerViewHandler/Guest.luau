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
local STRAIGHT_DOT = 0.98
-- Animation names as this file calls them; the ids behind them live in the guest config.
local IDLE = "Idle"
local WALK = "Walk"
local SIT = "Sit"

--[[ Tables ]]--
local Guest = {}
Guest.__index = Guest

type Route = {
	Points: { Vector3 },
	Index: number,
	LookAt: Vector3?,
	OnArrive: (() -> ())?,
	Deadline: number,
	NextMoveAt: number,
}
type Seating = {
	Seat: Seat,
	Deadline: number,
	NextTryAt: number,
	OnSeated: () -> (),
	OnFailed: () -> (),
	StartFrame: CFrame,
	Lift: number,
	Adjusted: boolean,
}

export type Guest = typeof(setmetatable(
	{} :: {
		Janitor: any,
		Model: Model,
		Humanoid: Humanoid,
		Root: BasePart,
		Tracks: { [string]: AnimationTrack },
		Playing: string?,
		Route: Route?,
		RouteRevision: number,
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
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local ids = {
		[IDLE] = GuestsConfig.Avatar.IdleAnimation,
		[WALK] = GuestsConfig.Avatar.WalkAnimation,
		[SIT] = GuestsConfig.Avatar.SitAnimation,
	}

	local tracks = {}
	for name, id in ids do
		local animation = Instance.new("Animation")
		animation.AnimationId = id

		tracks[name] = (animator :: Animator):LoadAnimation(animation)
		animation:Destroy()
	end

	return tracks
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
	humanoid.WalkSpeed = GuestsConfig.WalkSpeed

	for _, piece in rig:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.CollisionGroup = CollisionConfig.Groups.Guest
		end
	end

	-- Moved by the root, not by the pivot: a rig without a primary part pivots around its bounding box.
	root.CFrame = CFrame.new(position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
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
		TickHandler.Tick:Connect(function()
			self:Update(os.clock())
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

	for trackName, track in self.Tracks do
		if trackName ~= name then
			track:Stop()
		end
	end

	self.Tracks[name]:Play()
	if name == WALK then
		self.Tracks[name]:AdjustSpeed(self.Humanoid.WalkSpeed / 8)
	end
	self.Playing = name
end

-- The shared tick owns progress, so cancelling a route leaves no MoveToFinished waiter behind.
function Guest.WalkRoute(self: Guest, points: { Vector3 }, lookAt: Vector3?, onArrive: (() -> ())?): ()
	if self.Destroyed then
		return
	end
	self.Janitor:Remove("Turn")
	self.Janitor:Remove("SeatMotion")
	self.Seating = nil
	self.StandingUntil = nil
	local now = os.clock()
	self.RouteRevision += 1
	self.Route = {
		Points = points,
		Index = 1,
		LookAt = lookAt,
		OnArrive = onArrive,
		Deadline = now + GuestsConfig.WalkTimeout,
		NextMoveAt = 0,
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
	self.Humanoid.AutoRotate = true
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	self.Humanoid.Sit = false
	self:Play(WALK)
	self:Update(now)
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

function Guest.Update(self: Guest, now: number): ()
	if self.Destroyed then
		return
	end
	if self.Playing == WALK then
		self.Tracks[WALK]:AdjustSpeed(self.Humanoid.WalkSpeed / 8)
	end
	if not self.Model.Parent or (self.ExitAt and now >= self.ExitAt) then
		self:Destroy()
		return
	end
	if self.FadeEndsAt then
		if now >= self.FadeEndsAt then
			self:Destroy()
		end
		return
	end
	if self.StandingUntil then
		if now < self.StandingUntil and self.Humanoid.SeatPart then
			return
		end
		self.StandingUntil = nil
		self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		self.Humanoid.Sit = false
		self.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		self.Root.AssemblyLinearVelocity = Vector3.zero
		self.Root.AssemblyAngularVelocity = Vector3.zero
		self.Humanoid.AutoRotate = true
		self:Play(WALK)
		if self.Route then
			self.Route.Deadline = now + GuestsConfig.WalkTimeout
		end
	end
	if self.Seating then
		self:UpdateSeating(now)
		return
	end
	local route = self.Route
	if not route then
		return
	end
	local point = route.Points[route.Index]
	-- Humanoid stops about one stud before its goal. Hand off a straight leg early and
	-- issue its next MoveTo in this update; waiting another 10 Hz tick causes stop/start motion.
	while point do
		local delta = (point - self.Root.Position) * Vector3.new(1, 0, 1)
		local threshold = ARRIVE_DISTANCE
		local nextPoint = route.Points[route.Index + 1]
		if nextPoint and delta.Magnitude > 0 then
			local outgoing = (nextPoint - point) * Vector3.new(1, 0, 1)
			if outgoing.Magnitude > 0 and delta.Unit:Dot(outgoing.Unit) >= STRAIGHT_DOT then
				threshold = GuestsConfig.WaypointReachDistance
			end
		end
		if delta.Magnitude >= threshold then
			break
		end
		route.Index += 1
		route.Deadline = now + GuestsConfig.WalkTimeout
		route.NextMoveAt = 0
		point = route.Points[route.Index]
	end
	if not point then
		self.Route = nil
		local revision = self.RouteRevision
		-- A porch callback can continue directly into the cafe. Do not snap, zero velocity
		-- or briefly play Idle when that callback starts the next route on the same body.
		if route.OnArrive then
			route.OnArrive()
		end
		if self.Destroyed or self.RouteRevision ~= revision then
			return
		end
		self.Humanoid:MoveTo(self.Root.Position)
		self.Root.AssemblyLinearVelocity = Vector3.zero
		self.Root.AssemblyAngularVelocity = Vector3.zero
		self.Humanoid.AutoRotate = false
		self:Play(IDLE)
		if route.LookAt and not self.Seating then
			self:FaceTowards(route.LookAt)
		end
		return
	end
	-- Failed routes retire in place; moving a stuck body through walls hides navigation defects.
	if now >= route.Deadline then
		self.Route = nil
		self.Humanoid:MoveTo(self.Root.Position)
		local onBlocked = self.OnBlocked
		self.OnBlocked = nil
		if onBlocked then
			onBlocked()
		end
		if not self.Destroyed then
			self.Route = nil
			self:FadeOut()
		end
		return
	end
	if now >= route.NextMoveAt then
		self.Humanoid:MoveTo(point)
		route.NextMoveAt = now + GuestsConfig.MoveRefreshSeconds
	end
end

function Guest.FaceTowards(self: Guest, lookAt: Vector3): ()
	local flat = Vector3.new(lookAt.X, self.Root.Position.Y, lookAt.Z)
	if (flat - self.Root.Position).Magnitude < ARRIVE_DISTANCE then
		return
	end

	local tween = TweenService:Create(self.Root, TweenInfo.new(GuestsConfig.TurnSeconds), {
		CFrame = CFrame.lookAt(self.Root.Position, flat),
	})
	self.Janitor:Add(tween, "Cancel", "Turn")
	tween:Play()
end

-- Seat:Sit may be refused during cooldown or by another occupant. Confirm physics before the HUD.
function Guest.SitOn(self: Guest, seat: Seat, onSeated: () -> (), onFailed: () -> ()): ()
	self.Janitor:Remove("Turn")
	self.Janitor:Remove("SeatMotion")
	self.StandingUntil = nil
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
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
	self.ApproachFrame = self.Root.CFrame
	self.Seating = {
		Seat = seat,
		Deadline = os.clock() + GuestsConfig.SeatTimeout,
		NextTryAt = 0,
		OnSeated = onSeated,
		OnFailed = onFailed,
		StartFrame = self.Root.CFrame,
		Lift = lift + seat.Size.Y / 2,
		Adjusted = false,
	}
end

function Guest.UpdateSeating(self: Guest, now: number): ()
	local pending = self.Seating
	if not pending then
		return
	end
	local seat = pending.Seat
	local weld = seat:FindFirstChild("SeatWeld")
	if not pending.Adjusted and weld and weld:IsA("Weld") and weld.Part1 == self.Root then
		pending.Adjusted = true
		self:Play(SIT)
		-- Roblox's fixed seat offset floats scaled avatars. Fit the pelvis to the cushion,
		-- and interpolate the weld from the approach pose so seating does not teleport.
		weld.C0 = seat.CFrame:ToObjectSpace(pending.StartFrame) * weld.C1
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
		pending.OnFailed()
		return
	end
	if now >= pending.NextTryAt and not seat.Occupant then
		seat:Sit(self.Humanoid)
		pending.NextTryAt = now + GuestsConfig.MoveRefreshSeconds
		-- SeatWeld is normally created synchronously; set its starting pose before physics.
		if seat:FindFirstChild("SeatWeld") then
			self:UpdateSeating(now)
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
