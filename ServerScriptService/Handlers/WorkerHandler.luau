--!strict
-- Bakery workers with a body (Configs/Workers): the Helper and the Auto-Cleaner.
--
-- The Helper is the assistant made visible. It stands in the café whenever the owner has an
-- assistant slot (the upgrade or the Hire a Helper pass) and walks to every job AssistantHandler
-- reports. The Cleaner exists while the owner has the Auto-Cleaner pass; its jobs are decided here:
-- every CleanerInterval it walks to a puddle or a dirty table, cleans it on arrival and walks back.
--
-- Bodies reuse the guests' walker (CustomerViewHandler/Guest) and generated avatars
-- (CustomerViewHandler/Appearance): server-owned rigs in the Guest collision group, so they pass
-- through props and players and only walls stop them. The kitchen is reached through the arch.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers
local _CustomerView = _Handlers.CustomerViewHandler

--[[ Modules ]]--
local Appearance = require(_CustomerView.Appearance)
local AssistantHandler = require(_Handlers.AssistantHandler)
local BaseHandler = require(_Handlers.BaseHandler)
local BuildingHandler = require(_Handlers.BuildingHandler)
local CarpetRoute = require(_CustomerView.CarpetRoute)
local CharacterAnimations = require(_Configs.CharacterAnimations)
local CleaningHandler = require(_Handlers.CleaningHandler)
local Config = require(_Configs.Workers)
local DataHandler = require(_Handlers.DataHandler)
local DataList = require(_Shared.DataList)
local Guest = require(_CustomerView.Guest)
local LoggerUtil = require(_Shared.Libs.Logger)
local MonetizationAssets = require(_Shared.MonetizationAssets)
local TableHandler = require(_Handlers.TableHandler)
local Theme = require(_Shared.UI.Theme)
local TutorialPolicy = require(_Shared.TutorialPolicy)
local UpgradeHandler = require(_Handlers.UpgradeHandler)

--[[ Constants ]]--
local RECONCILE_SECONDS = 2
local APPROACH_DISTANCE = 2.5

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "WorkerHandler" })
-- Accessory templates already reported missing, so the console names each one once.
local warnedTemplates: { [string]: boolean } = {}

--[[ Types ]]--
type Body = {
	Kind: string,
	Guest: Guest.Guest,
	Paid: boolean,
	-- Bumped by every new walk, so a stale arrival callback does nothing.
	Job: number,
}

type Crew = {
	Bodies: { [string]: Body },
	Spawning: { [string]: boolean },
	Folder: Folder,
	NextClean: number,
	CleanerBusy: boolean,
}

--[[ Tables ]]--
local WorkerHandler = {
	dependencies = {
		"DataHandler",
		"BaseHandler",
		"BuildingHandler",
		"UpgradeHandler",
		"AssistantHandler",
		"CleaningHandler",
		"TableHandler",
		"CustomerViewHandler",
	},
}

--[[ Private Functions ]]--
local function ownsPass(player: Player, passId: string): boolean
	local data = DataHandler:GetData(player)
	return data ~= nil and DataList.Contains(data.Cloud.Passes, passId)
end

local function toWorld(player: Player, point: Vector3): Vector3?
	local transform = BaseHandler:GetTransform(player)
	return transform and transform * point
end

local function toTemplate(player: Player, point: Vector3): Vector3?
	local transform = BaseHandler:GetTransform(player)
	return transform and transform:PointToObjectSpace(point)
end

-- A point just short of `target` on the way from `from`, so the worker stops beside the job.
local function approach(from: Vector3, target: Vector3): Vector3
	local flat = Vector3.new(from.X - target.X, 0, from.Z - target.Z)
	if flat.Magnitude < APPROACH_DISTANCE then
		return Vector3.new(target.X, from.Y, target.Z)
	end
	local stop = target + flat.Unit * APPROACH_DISTANCE
	return Vector3.new(stop.X, from.Y, stop.Z)
end

-- World height of a part's highest point, whatever its rotation.
local function topOf(part: BasePart): number
	local frame, half = part.CFrame, part.Size / 2
	local reach = math.abs(frame.RightVector.Y) * half.X
		+ math.abs(frame.UpVector.Y) * half.Y
		+ math.abs(frame.LookVector.Y) * half.Z
	return frame.Position.Y + reach
end

-- The top of the head and of what is worn on it (an accessory whose handle attaches to one of the
-- head's attachments, such as a hat). Back-worn tools and held props are left out, so a mop handle
-- sticking up behind the shoulders does not lift the tag.
local function headTop(rig: Model, head: BasePart): number
	local top = topOf(head)
	for _, accessory in rig:GetChildren() do
		local handle = if accessory:IsA("Accessory") then accessory:FindFirstChild("Handle") else nil
		if not handle or not handle:IsA("BasePart") then
			continue
		end
		for _, child in handle:GetChildren() do
			if child:IsA("Attachment") and head:FindFirstChild(child.Name) then
				top = math.max(top, topOf(handle))
				break
			end
		end
	end
	return top
end

-- A tag line: bare text in the HUD's font, in a band of the tag's height, with a thick dark outline
-- when `outlined`.
local function addTagLine(
	billboard: BillboardGui,
	name: string,
	text: string,
	top: number,
	height: number,
	outlined: boolean
): TextLabel
	local tag = Config.Tag
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, top + height / 2)
	label.Size = UDim2.fromScale(0.94, height * 0.86)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.FontFace = Theme.Fonts.ExtraBold
	label.TextColor3 = tag.Text
	label.ZIndex = 1
	label.Parent = billboard
	if outlined then
		local outline = Instance.new("UIStroke")
		outline.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		outline.Thickness = tag.OutlineScale
		outline.Color = tag.Outline
		outline.LineJoinMode = Enum.LineJoinMode.Round
		outline.Parent = label
	end
	return label
end

-- The name tag: the name over a caption saying what the worker does, sized in studs over the top
-- of the hat (read once the accessories are on). Paid workers' name gets the holographic gradient
-- over a soft glow; WorkerTagHandler slides both gradients on each client.
local function addLabel(rig: Model, head: BasePart, worker: Config.Worker, paid: boolean): ()
	local tag = Config.Tag
	local top = headTop(rig, head)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorkerLabel"
	billboard.Size = UDim2.fromScale(tag.Size.X, tag.Size.Y)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, top - head.Position.Y + tag.Gap + tag.Size.Y / 2, 0)
	billboard.MaxDistance = tag.MaxDistance
	billboard.LightInfluence = 0
	billboard.ClipsDescendants = false
	billboard.Adornee = head
	billboard.Parent = head

	local nameShare = tag.NameShare
	if paid then
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, nameShare / 2)
		glow.Size = UDim2.fromScale(tag.GlowSize.X, tag.GlowSize.Y * nameShare)
		glow.BackgroundTransparency = 1
		glow.Image = tag.Glow
		glow.ImageTransparency = tag.GlowTransparency
		glow.ZIndex = 0
		glow.Parent = billboard
		local glowGradient = Instance.new("UIGradient")
		glowGradient.Name = tag.HoloName
		glowGradient.Color = Config.HoloColors(-tag.Holo.GlowLag, tag.Holo.GlowSaturation)
		glowGradient.Parent = glow
	end

	local label = addTagLine(billboard, "Label", worker.Label, 0, nameShare, true)
	if paid then
		local gradient = Instance.new("UIGradient")
		gradient.Name = tag.HoloName
		gradient.Color = Config.HoloColors(0, tag.Holo.Saturation)
		gradient.Parent = label
	end
	local roleCentre = nameShare + (1 - nameShare) / 2
	local chip = Instance.new("Frame")
	chip.Name = "RoleChip"
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Position = UDim2.fromScale(0.5, roleCentre)
	chip.Size = UDim2.fromScale(tag.RoleChipSize.X, tag.RoleChipSize.Y)
	chip.BackgroundColor3 = tag.RoleChip
	chip.BackgroundTransparency = tag.RoleChipTransparency
	chip.ZIndex = 0
	chip.Parent = billboard
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = Theme.Corners.Pill
	chipCorner.Parent = chip
	local role = addTagLine(billboard, "Role", worker.Role, nameShare, 1 - nameShare, false)
	role.Size = UDim2.fromScale(tag.RoleChipSize.X - 0.1, tag.RoleChipSize.Y * 0.8)
	role.TextColor3 = tag.RoleText
end

-- Paid workers stand in a soft pool of golden light on the floor, with a few star sparkles drifting
-- up around the body. The pool's copies cross-fade, so it holds still but breathes. It floats a
-- little over the feet, so a raised floor part (a build placeholder plank) does not cover it.
local function addAura(root: BasePart, humanoid: Humanoid): ()
	local aura = Config.Aura
	local attachment = Instance.new("Attachment")
	attachment.Name = "WorkerAura"
	attachment.Position = Vector3.new(0, -(root.Size.Y / 2 + humanoid.HipHeight) + aura.PoolLift, 0)
	attachment.Parent = root

	local pool = Instance.new("ParticleEmitter")
	pool.Name = "Pool"
	pool.Texture = aura.Pool
	pool.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pool.EmissionDirection = Enum.NormalId.Top
	pool.Speed = NumberRange.new(0.001)
	pool.LockedToPart = true
	pool.Rate = 1.2
	pool.Lifetime = NumberRange.new(2.5)
	pool.Rotation = NumberRange.new(0, 360)
	pool.Size = NumberSequence.new(aura.PoolSize * 0.9, aura.PoolSize)
	pool.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	pool.Color = ColorSequence.new(aura.Color)
	pool.LightEmission = 1
	pool.LightInfluence = 0
	pool.Brightness = 3
	pool.ZOffset = 0.5
	pool.Parent = attachment

	-- From the surface of a cylinder around the root, so they rise beside the body, not out of it.
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "WorkerSparkles"
	sparkles.Texture = aura.Sparkle
	sparkles.Shape = Enum.ParticleEmitterShape.Cylinder
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparkles.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Rate = 3
	sparkles.Lifetime = NumberRange.new(1.2, 1.8)
	sparkles.Speed = NumberRange.new(0.3, 0.6)
	sparkles.Acceleration = Vector3.new(0, 1.5, 0)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Color = ColorSequence.new(aura.Color)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Brightness = 3
	sparkles.Parent = root
end

-- Hats, tools and extras are Accessory templates in Shared/MonetizationAssets; a missing one is not
-- worn. The folder is authored content (not on disk), so a place whose Assets package lacks it still
-- runs the synced code and leaves the workers bare; the warning says so once per template.
local function wear(humanoid: Humanoid, templateName: string?): ()
	if not templateName then
		return
	end
	local template = MonetizationAssets.Find(templateName)
	if template and template:IsA("Accessory") then
		humanoid:AddAccessory(template:Clone())
	elseif not warnedTemplates[templateName] then
		warnedTemplates[templateName] = true
		Logger:Warn(`Worker accessory {templateName} is missing from {MonetizationAssets.Path}`)
	end
end

-- The tool rides on the back between jobs (its template welds to BodyBackAttachment) and is swapped
-- for its `<Tool>Held` template, gripped in the right hand, only while a clip that swings it plays,
-- so nothing sticks out of the idle hand. Swapping whole accessories keeps server and clients in
-- step; the Humanoid rebuilds accessory welds on each side.
local function holdTool(guest: Guest.Guest, toolName: string?, working: boolean): ()
	if not toolName then
		return
	end
	local wanted = if working then `{toolName}Held` else toolName
	local other = if working then toolName else `{toolName}Held`
	-- Without the other template the tool simply stays where it is.
	if guest.Model:FindFirstChild(wanted) or not MonetizationAssets.Find(wanted) then
		return
	end
	local current = guest.Model:FindFirstChild(other)
	if current and current:IsA("Accessory") then
		current:Destroy()
	end
	wear(guest.Humanoid, wanted)
end

-- The worker's own outfit: its catalog shirt and pants (Configs/Workers) instead of the guests'
-- fallback clothing, over skin-coloured arms and uniform-coloured torso and legs.
local function dress(rig: Model, worker: Config.Worker): ()
	for _, child in rig:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("Accessory") then
			child:Destroy()
		end
	end
	local colors = rig:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	colors.LeftArmColor3 = colors.HeadColor3
	colors.RightArmColor3 = colors.HeadColor3
	colors.TorsoColor3 = worker.Torso
	colors.LeftLegColor3 = worker.Legs
	colors.RightLegColor3 = worker.Legs
	colors.Parent = rig

	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = worker.Shirt
	shirt.Parent = rig
	local pants = Instance.new("Pants")
	pants.PantsTemplate = worker.Pants
	pants.Parent = rig
end

--[[ Handling ]]--
function WorkerHandler.OnInit(self: WorkerHandler): ()
	self.Crews = {}
end

function WorkerHandler.OnStart(self: WorkerHandler): ()
	local root = workspace:FindFirstChild(Config.FolderName) or Instance.new("Folder")
	root.Name = Config.FolderName
	root.Parent = workspace
	self.Root = root

	AssistantHandler.Acted:Connect(function(player: Player, position: Vector3)
		self:SendHelper(player, position)
	end)

	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:Dismiss(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		self:Dismiss(player)
	end)

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				-- Its own thread, so one player's error is reported without stopping every crew.
				task.spawn(function()
					self:Reconcile(player)
				end)
			end
			task.wait(RECONCILE_SECONDS)
		end
	end)
end

--- Spawns or removes each worker to match what the owner has, and runs the Cleaner's job loop.
function WorkerHandler.Reconcile(self: WorkerHandler, player: Player): ()
	if not BaseHandler:GetBase(player) or not DataHandler:GetData(player) then
		return
	end

	local crew = self:GetCrew(player)
	local wantHelper = UpgradeHandler:HasStat(player, "AssistantSlots")
	local helperPaid = ownsPass(player, Config.HelperPass)
	local wantCleaner = ownsPass(player, Config.CleanerPass)

	self:Keep(player, crew, "Helper", wantHelper, helperPaid)
	self:Keep(player, crew, "Cleaner", wantCleaner, true)

	if crew.Bodies.Cleaner and not crew.CleanerBusy and os.clock() >= crew.NextClean then
		crew.NextClean = os.clock() + Config.CleanerInterval
		self:CleanNext(player, crew)
	end
end

function WorkerHandler.GetCrew(self: WorkerHandler, player: Player): Crew
	local crew = self.Crews[player]
	if crew then
		return crew
	end

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder.Parent = self.Root
	local created: Crew = { Bodies = {}, Spawning = {}, Folder = folder, NextClean = 0, CleanerBusy = false }
	self.Crews[player] = created
	return created
end

--- Keeps one worker of `kind` alive while wanted, rebuilt when its paid look changes.
function WorkerHandler.Keep(self: WorkerHandler, player: Player, crew: Crew, kind: string, wanted: boolean, paid: boolean): ()
	local body = crew.Bodies[kind]
	local stale = body ~= nil and (not wanted or body.Paid ~= paid or body.Guest.Destroyed)
	if body and stale then
		body.Guest:Destroy()
		crew.Bodies[kind] = nil
	end
	if not wanted or (body and not stale) or crew.Spawning[kind] then
		return
	end

	crew.Spawning[kind] = true
	task.spawn(function()
		local spawned = self:Spawn(player, crew, kind, paid)
		crew.Spawning[kind] = nil
		if spawned and self.Crews[player] == crew then
			crew.Bodies[kind] = spawned
		elseif spawned then
			spawned.Guest:Destroy()
		end
	end)
end

function WorkerHandler.Spawn(self: WorkerHandler, player: Player, crew: Crew, kind: string, paid: boolean): Body?
	local worker: Config.Worker = (Config :: any)[kind]

	-- Builds the avatar from a HumanoidDescription; yields on the web call.
	local rig = Appearance.Rig({ UserId = 0, Name = worker.Label, Key = `worker_{kind}`, Variant = worker.Variant })
	if not rig then
		Logger:Warn(`Could not build the {kind} for {player.Name}`)
		return nil
	end
	-- The owner can leave or lose the bakery during that yield.
	local idle = toWorld(player, worker.Idle)
	if self.Crews[player] ~= crew or not crew.Folder.Parent or not idle then
		rig:Destroy()
		return nil
	end
	dress(rig, worker)

	local guest = Guest.new(`{kind}_{player.UserId}`, worker.Label, rig, idle, crew.Folder)
	if not guest then
		return nil
	end
	guest.SpeedLimit = Config.WalkSpeed

	local humanoid = guest.Humanoid
	wear(humanoid, worker.Hat)
	wear(humanoid, worker.Tool)
	local extras: { string } = worker.Extras or {}
	for _, extra in extras do
		wear(humanoid, extra)
	end
	local head = rig:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		addLabel(rig, head, worker, paid)
	end
	if paid then
		addAura(guest.Root, humanoid)
	end
	rig:SetAttribute("Worker", kind)
	rig:SetAttribute("OwnerUserId", player.UserId)
	-- A body spawns with no heading of its own; a zero-length route turns it to face the room.
	guest:WalkRoute({ idle }, toWorld(player, worker.Face))

	return { Kind = kind, Guest = guest, Paid = paid, Job = 0 }
end

function WorkerHandler.Dismiss(self: WorkerHandler, player: Player): ()
	local crew = self.Crews[player]
	if not crew then
		return
	end
	self.Crews[player] = nil
	for _, body in crew.Bodies do
		body.Guest:Destroy()
	end
	crew.Folder:Destroy()
end

--- Route from the body to a world point, through the arch when it crosses between rooms.
function WorkerHandler.Route(_self: WorkerHandler, player: Player, from: Vector3, to: Vector3): { Vector3 }
	local base = BaseHandler:GetBase(player)
	local fromLocal = toTemplate(player, from)
	local toLocal = toTemplate(player, to)
	local archCafe = toWorld(player, Config.ArchCafe)
	local archKitchen = toWorld(player, Config.ArchKitchen)
	if not fromLocal or not toLocal or not archCafe or not archKitchen then
		return { to }
	end

	local fromKitchen = fromLocal.X > Config.ArchX
	local toKitchen = toLocal.X > Config.ArchX
	if fromKitchen == toKitchen then
		return if toKitchen then { to } else CarpetRoute.Build(base, from, to)
	end

	local points: { Vector3 } = {}
	if fromKitchen then
		table.insert(points, archKitchen)
		table.insert(points, archCafe)
		for _, point in CarpetRoute.Build(base, archCafe, to) do
			table.insert(points, point)
		end
	else
		for _, point in CarpetRoute.Build(base, from, archCafe) do
			table.insert(points, point)
		end
		table.insert(points, archKitchen)
		table.insert(points, to)
	end
	return points
end

-- The player's own work clip (CharacterAnimations.Clips), looped on the worker for `seconds`.
local function playClip(guest: Guest.Guest, clipName: string, seconds: number, toolName: string?): ()
	local clip = CharacterAnimations.Clips[clipName]
	local animator = guest.Humanoid:FindFirstChildOfClass("Animator")
	if not clip or not animator or guest.Destroyed then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = clip.Id
	local track = animator:LoadAnimation(animation)
	animation:Destroy()
	track.Priority = clip.Priority
	track.Looped = true
	local held = Config.WorkGripClips[clipName] == true
	if held then
		holdTool(guest, toolName, true)
	end
	track:Play(CharacterAnimations.FadeTime)
	task.delay(seconds, function()
		track:Stop(CharacterAnimations.FadeTime)
		task.delay(CharacterAnimations.FadeTime, function()
			track:Destroy()
			if held and not guest.Destroyed then
				holdTool(guest, toolName, false)
			end
		end)
	end)
end

--- Walks a body to a job, runs `work` there (after `pause` seconds) and walks it back to its spot.
function WorkerHandler.Walk(
	self: WorkerHandler,
	player: Player,
	body: Body,
	target: Vector3,
	pause: number,
	clip: string?,
	work: (() -> ())?,
	finished: (() -> ())?
): ()
	body.Job += 1
	local job = body.Job
	local guest = body.Guest
	-- A job belongs to the bakery it was found in; a crew rebuilt meanwhile (a new bakery) skips it.
	local crew = self.Crews[player]
	local worker: Config.Worker = (Config :: any)[body.Kind]
	local stop = approach(guest.Root.Position, target)

	local function back(): ()
		local idle = toWorld(player, worker.Idle)
		if idle and not guest.Destroyed and body.Job == job then
			guest:WalkRoute(self:Route(player, guest.Root.Position, idle), toWorld(player, worker.Face))
		end
		if finished then
			finished()
		end
	end

	local done = false
	local function arrive(): ()
		if done then
			return
		end
		done = true
		if clip then
			playClip(guest, clip, pause, worker.Tool)
		end
		task.delay(pause, function()
			-- The job is server state, so it runs even if a stuck body has faded out on the way.
			if work and crew and self.Crews[player] == crew then
				work()
			end
			back()
		end)
	end

	guest:WalkRoute(self:Route(player, guest.Root.Position, stop), target, arrive)
	-- A walk that never arrives (a stuck body) still does its job and frees the worker.
	task.delay(Config.WalkTimeout, function()
		if body.Job == job then
			arrive()
		end
	end)
end

function WorkerHandler.SendHelper(self: WorkerHandler, player: Player, position: Vector3): ()
	local crew = self.Crews[player]
	local body = crew and crew.Bodies.Helper
	if body and not body.Guest.Destroyed then
		self:Walk(player, body, position, 0.6, nil, nil, nil)
	end
end

--- The Cleaner's next job: a puddle first (they block the kitchen), then a dirty table.
function WorkerHandler.CleanNext(self: WorkerHandler, player: Player, crew: Crew): ()
	local body = crew.Bodies.Cleaner
	if not body then
		return
	end

	-- The introduction teaches mopping with its own puddle, so the floor is the player's until then.
	local data = DataHandler:GetData(player)
	local spillId, spill = nil, nil
	if data and not TutorialPolicy.IsActive(data.Cloud) then
		spillId, spill = CleaningHandler:FindSpill(player)
	end
	local target: Vector3? = spill and spill.Position
	local work: (() -> ())? = nil
	local clip = Config.SpillClip
	if spillId and target then
		work = function()
			CleaningHandler:CleanByWorker(player, spillId)
		end
	else
		-- The introduction's teaching table is the player's to wipe, so the Cleaner passes over it.
		local context = data and data.Session.Tutorial
		local protected = if context and context.Protected then context.TableId else nil
		local tableId = TableHandler:FindDirty(player, protected)
		local building = tableId and BuildingHandler:GetBuilding(player, tableId)
		target = building and building.Part.Position
		clip = Config.TableClip
		if tableId and target then
			work = function()
				TableHandler:Clean(player, tableId)
			end
		end
	end
	if not target or not work then
		return
	end

	crew.CleanerBusy = true
	self:Walk(player, body, target, Config.CleanSeconds, clip, work, function()
		crew.CleanerBusy = false
	end)
end

export type WorkerHandler = typeof(WorkerHandler) & {
	Crews: { [Player]: Crew },
	Root: Instance,
}

return WorkerHandler :: WorkerHandler
