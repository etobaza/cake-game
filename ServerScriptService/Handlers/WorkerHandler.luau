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
local TableHandler = require(_Handlers.TableHandler)
local TutorialPolicy = require(_Shared.TutorialPolicy)
local UpgradeHandler = require(_Handlers.UpgradeHandler)

--[[ Constants ]]--
local RECONCILE_SECONDS = 2
local APPROACH_DISTANCE = 2.5
local LABEL_COLOR = Color3.fromRGB(255, 255, 255)
local PAID_LABEL_COLOR = Color3.fromRGB(255, 214, 90)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "WorkerHandler" })

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

local function addLabel(head: BasePart, text: string, paid: boolean): ()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorkerLabel"
	billboard.Size = UDim2.fromOffset(140, 30)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = if paid then PAID_LABEL_COLOR else LABEL_COLOR
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(70, 35, 15)
	stroke.Parent = label
end

local function addAura(root: BasePart): ()
	local attachment = Instance.new("Attachment")
	attachment.Name = "WorkerAura"
	attachment.Parent = root

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = Config.AuraSparkle
	sparkles.Rate = 5
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(0.5, 1.2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140))
	sparkles.Shape = Enum.ParticleEmitterShape.Cylinder
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparkles.Parent = attachment

	local glow = Instance.new("ParticleEmitter")
	glow.Name = "Glow"
	glow.Texture = Config.AuraGlow
	glow.Rate = 1
	glow.Lifetime = NumberRange.new(2)
	glow.Speed = NumberRange.new(0)
	glow.LockedToPart = true
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.ZOffset = -1
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4.5),
		NumberSequenceKeypoint.new(0.5, 5.2),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
	glow.Parent = attachment
end

-- Hats and tools are Accessory templates in MonetizationAssets; a missing one is simply not worn.
local function wear(humanoid: Humanoid, templateName: string?): ()
	if not templateName then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("MonetizationAssets")
	local template = assets and assets:FindFirstChild(templateName)
	if template and template:IsA("Accessory") then
		humanoid:AddAccessory(template:Clone())
	end
end

-- The worker's own outfit. The engine colours an R15 limb as one piece (the hand follows the arm),
-- so the sleeves come from a plain white shirt template tinted to the uniform: it covers the torso
-- and arms down to the wrist and leaves the hands clear, over arms coloured like the skin.
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
	shirt.ShirtTemplate = Config.ShirtTemplate
	shirt.Color3 = worker.Torso
	shirt.Parent = rig
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
	local head = rig:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		addLabel(head, worker.Label, paid)
	end
	if paid then
		addAura(guest.Root)
	end
	rig:SetAttribute("Worker", kind)
	rig:SetAttribute("OwnerUserId", player.UserId)

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

-- A held tool can carry a second grip for work: the mop hangs from IdleGrip while walking and
-- switches to WorkGrip (the player's broom hold) while a clip that swings it plays.
local function setGrip(guest: Guest.Guest, name: string): ()
	for _, accessory in guest.Model:GetChildren() do
		local handle = if accessory:IsA("Accessory") then accessory:FindFirstChild("Handle") else nil
		local grip = handle and handle:FindFirstChild("RightGripAttachment")
		local pose = handle and handle:FindFirstChild(name)
		if grip and grip:IsA("Attachment") and pose and pose:IsA("Attachment") then
			grip.CFrame = pose.CFrame
		end
	end
end

-- The player's own work clip (CharacterAnimations.Clips), looped on the worker for `seconds`.
local function playClip(guest: Guest.Guest, clipName: string, seconds: number): ()
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
		setGrip(guest, "WorkGrip")
	end
	track:Play(CharacterAnimations.FadeTime)
	task.delay(seconds, function()
		track:Stop(CharacterAnimations.FadeTime)
		task.delay(CharacterAnimations.FadeTime, function()
			track:Destroy()
			if held and not guest.Destroyed then
				setGrip(guest, "IdleGrip")
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
	local worker: Config.Worker = (Config :: any)[body.Kind]
	local stop = approach(guest.Root.Position, target)

	local function back(): ()
		local idle = toWorld(player, worker.Idle)
		if idle and not guest.Destroyed and body.Job == job then
			guest:WalkRoute(self:Route(player, guest.Root.Position, idle))
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
			playClip(guest, clip, pause)
		end
		task.delay(pause, function()
			-- The job is server state, so it runs even if a stuck body has faded out on the way.
			if work and self.Crews[player] then
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
