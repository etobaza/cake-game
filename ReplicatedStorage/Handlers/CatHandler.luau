--!strict
-- Authored cat rigs stay at their habitats; only their bone poses and care prompts are local.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.Cats)
local DataClient = require(script.Parent.DataHandlerClient)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "CatHandler" })

type Joint = { Bone: Bone, Rest: CFrame, Parent: Bone? }
type Visual = { Janitor: any, Step: (number) -> () }
local CatHandler = { dependencies = { "DataClient" } }

local function prop(name: string, size: Vector3, color: Color3, frame: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name, part.Size, part.Color, part.CFrame = name, size, color, frame
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.Parent = parent
	return part
end

local function bind(model: Model): Visual
	local janitor = Janitor.new()
	local part: MeshPart? = nil
	local prompt: ProximityPrompt? = nil
	local toy: Part? = nil
	local milk: Part? = nil
	local bowl: Part? = nil
	local joints: { Joint } = {}
	local seen: { [Bone]: boolean } = {}
	local poses: { [Bone]: CFrame } = {}
	local sourceFrame: CFrame? = nil
	local animator: Animator? = nil
	local tracks: { [string]: AnimationTrack } = {}
	local requested: { [string]: number } = {}
	local warned: { [string]: boolean } = {}
	local currentTrack: AnimationTrack? = nil
	local alive = true

	local function discover(): ()
		part = model:FindFirstChildWhichIsA("MeshPart", true)
		if not part then
			return
		end
		sourceFrame = part.CFrame
		for _, descendant in part:GetDescendants() do
			if descendant:IsA("Bone") and not seen[descendant] then
				seen[descendant] = true
				local parentBone = descendant.Parent
				table.insert(joints, {
					Bone = descendant,
					Rest = part.CFrame:ToObjectSpace(descendant.WorldCFrame),
					Parent = if parentBone and parentBone:IsA("Bone") then parentBone else nil,
				})
			end
		end
		-- Explicit parent order also handles bones arriving separately during replication.
		local function depth(bone: Bone): number
			local count = 0
			local parent = bone.Parent
			while parent and parent:IsA("Bone") do
				count += 1
				parent = parent.Parent
			end
			return count
		end
		table.sort(joints, function(a: Joint, b: Joint): boolean
			return depth(a.Bone) < depth(b.Bone)
		end)
		if not animator and #joints > 0 then
			-- Every client animates its streamed cats locally; gameplay remains server-owned.
			local controller = Instance.new("AnimationController")
			controller.Name = "CatAnimations"
			controller.Parent = model
			local catAnimator = Instance.new("Animator")
			catAnimator.Parent = controller
			animator = catAnimator
			janitor:Add(controller, "Destroy")
		end
		if not prompt and model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			local care = Instance.new("ProximityPrompt")
			care.Name = "CatCare"
			care.Style = Enum.ProximityPromptStyle.Custom
			care.ActionText, care.ObjectText = "Pet", "Cat"
			care.KeyboardKeyCode, care.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
			care.MaxActivationDistance = Config.InteractDistance
			care.RequiresLineOfSight = false
			care.Enabled = false
			care.Parent = part
			prompt = care
			janitor:Add(care, "Destroy")
			janitor:Add(
				care.Triggered:Connect(function()
					local id = model:GetAttribute("CatId")
					if care.Enabled and typeof(id) == "string" then
						Bus.Cafe.CatInteract:Fire(id)
					end
				end),
				"Disconnect"
			)
		end
		if model:GetAttribute("CatSlot") == "Play" and not toy then
			local frame = part.CFrame * CFrame.new(-part.Size.X * 0.48, -part.Size.Y / 2 + 0.2, 0)
			local toyPart = prop("CatToy", Vector3.one * 0.4, Color3.fromRGB(239, 152, 183), frame, model)
			toyPart.Shape = Enum.PartType.Ball
			janitor:Add(toyPart, "Destroy")
			local bowlPart = prop(
				"CatBowl",
				Vector3.new(0.16, 0.65, 0.65),
				Color3.fromRGB(72, 188, 190),
				frame * CFrame.Angles(0, 0, math.pi / 2),
				model
			)
			bowlPart.Shape = Enum.PartType.Cylinder
			local milkPart = prop(
				"CatMilk",
				Vector3.new(0.025, 0.5, 0.5),
				Color3.fromRGB(255, 250, 230),
				bowlPart.CFrame + Vector3.new(0, 0.085, 0),
				model
			)
			milkPart.Shape = Enum.PartType.Cylinder
			janitor:Add(bowlPart, "Destroy")
			janitor:Add(milkPart, "Destroy")
			toy, bowl, milk = toyPart, bowlPart, milkPart
		end
	end
	janitor:Add(
		model.DescendantAdded:Connect(function(d: Instance)
			if d:IsA("Bone") or d:IsA("MeshPart") then
				discover()
			end
		end),
		"Disconnect"
	)
	-- Tags, descendants and attributes may arrive in separate replication updates.
	for _, attribute in { "OwnerUserId", "CatSlot" } do
		janitor:Add(model:GetAttributeChangedSignal(attribute):Connect(discover), "Disconnect")
	end
	discover()

	local function playClip(pose: string?, now: number): boolean
		local name = if pose then Config.ClipByPose[pose] else nil
		local id = name and Config.Animations[name]
		local track = name and tracks[name]
		if name and id and animator and not requested[name] then
			requested[name] = now
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			janitor:Add(animation, "Destroy")
			local owner = animator
			local ok, loaded = pcall(function(): AnimationTrack
				return owner:LoadAnimation(animation)
			end)
			if not alive then
				if ok then
					loaded:Destroy()
				end
				return false
			end
			if ok then
				loaded.Looped = true
				loaded.Priority = Enum.AnimationPriority.Idle
				tracks[name] = loaded
				janitor:Add(loaded, "Destroy")
				track = loaded
			else
				warned[name] = true
				Logger:Warn(`Cannot load cat animation {name} ({id}): {loaded}`)
			end
		end
		local ready = track ~= nil and track.Length > 0
		if currentTrack and (not ready or currentTrack ~= track) then
			currentTrack:Stop(if ready then Config.AnimationFade else 0)
			currentTrack = nil
		end
		if not track or track.Length <= 0 then
			if
				name
				and requested[name]
				and not warned[name]
				and now - requested[name] >= Config.AnimationLoadTimeout
			then
				warned[name] = true
				Logger:Warn(`Cat animation {name} ({id}) has not loaded; using procedural pose`)
			end
			return false
		end
		if currentTrack ~= track then
			for _, joint in joints do
				if joint.Bone.Parent then
					joint.Bone.Transform = CFrame.identity
				end
			end
			track:Play(Config.AnimationFade)
			local seed = (model:GetAttribute("CatSeed") :: number?) or 0
			track.TimePosition = (now + seed) % track.Length
			currentTrack = track
		end
		return true
	end

	local function step(now: number): ()
		local mesh = part
		if not mesh or not mesh.Parent then
			return
		end
		local pose = model:GetAttribute("CatPose") :: string?
		local petting = ((model:GetAttribute("CatPetUntil") :: number?) or 0) > now
		local t = now + ((model:GetAttribute("CatSeed") :: number?) or 0)
		local scale = mesh.Size.X / 5.465
		local floor = -mesh.Size.Y / 2
		local usingClip = playClip(pose, now)
		for _, joint in joints do
			-- Animator is the only bone writer while an authored clip is active.
			if usingClip then
				break
			end
			local bone, rest = joint.Bone, joint.Rest
			if not bone.Parent then
				continue
			end
			local name = bone.Name
			local p = rest.Position
			local isHead = name == "Head"
			local isTail = name == "Root.001" or name == "Root.002"
			local front = p.X < -0.4 * scale
			local lift, turn = 0, CFrame.identity
			local compression = if pose == "Lay"
				then (if isHead then 0.8 else 0.6)
				elseif pose == "Sit" then (if front then 1 else 0.65)
				else 1
			local y = floor + (p.Y - floor) * compression
			if name == "UpperTorso" or name == "Root" then
				lift = math.sin(t * 1.8) * 0.015 * scale
			end
			if isHead then
				local nod = if pose == "Drink" then -0.3 + math.sin(t * 6) * 0.07 else math.sin(t * 0.8) * 0.06
				turn =
					CFrame.Angles(0, math.sin(t * 0.6) * 0.12, if petting then 0.16 + math.sin(t * 7) * 0.07 else nod)
			end
			if isTail then
				turn = CFrame.Angles(0, math.sin(t * (if petting then 4 else 1.5)) * 0.14, 0)
			end
			if pose == "Play" and front and not isHead then
				lift += math.max(0, math.sin(t * 3 + (if p.Z > 0 then 0 else math.pi))) * 0.3 * scale
			end
			if pose == "Scratch" and front and not isHead then
				lift += (0.65 + math.sin(t * 7 + (if p.Z > 0 then 0 else math.pi)) * 0.18) * scale
			end
			if pose == "Scratch" and isHead then
				lift += 0.22 * scale
			end
			local target = CFrame.new(p.X, y + lift, p.Z) * turn * rest.Rotation
			poses[bone] = target
			local parent = (if joint.Parent then poses[joint.Parent] else nil) or CFrame.identity
			bone.Transform = (parent * bone.CFrame):ToObjectSpace(target)
		end
		local fed = model:GetAttribute("CatFed") == true
		if toy and sourceFrame then
			toy.Transparency = if fed then 1 else 0
			toy.CFrame = sourceFrame * CFrame.new(-mesh.Size.X * 0.48, floor + 0.2, math.sin(t * 3) * 0.12)
		end
		if bowl then
			bowl.Transparency = if fed then 0 else 1
		end
		if milk then
			milk.Transparency = if fed then 0 else 1
		end
		if prompt then
			local ready = DataClient:IsReady()
			local day = if ready then DataClient:GetData({ "Day" }, "Session") else nil
			local hands = if ready then DataClient:GetData({ "Hands" }, "Session") else nil
			local held = hands and hands[#hands]
			local canFeed = held
				and held.Kind == "Ingredient"
				and held.Id == "milk"
				and model:GetAttribute("CatSlot") == "Play"
				and not fed
			prompt.Enabled = day ~= nil
				and (day.Phase == "Prep" or day.Phase == "Shift")
				and not model:GetAttribute("CatReserved")
				and not petting
				and (held == nil or canFeed == true)
			prompt.ActionText = if canFeed then "Give milk" else "Pet"
			prompt.ObjectText = if fed then "Cat · enjoying milk" else "Cat"
		end
	end
	janitor:Add(function()
		alive = false
		for _, track in tracks do
			track:Stop(0)
		end
		for _, joint in joints do
			if joint.Bone.Parent then
				joint.Bone.Transform = CFrame.identity
			end
		end
	end, true)
	return { Janitor = janitor, Step = step }
end

function CatHandler.OnInit(self: CatHandler): ()
	self.Janitor = Janitor.new()
	self.Cats = {}
end

function CatHandler.OnStart(self: CatHandler): ()
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(function(instance)
			self:Track(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(instance)
			self:Untrack(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Config.Tag) do
		self:Track(instance)
	end
	self.Janitor:Add(
		RunService.PreRender:Connect(function()
			local now = workspace:GetServerTimeNow()
			for _, visual in self.Cats do
				visual.Step(now)
			end
		end),
		"Disconnect"
	)
end

function CatHandler.Track(self: CatHandler, instance: Instance): ()
	if not instance:IsA("Model") or self.Cats[instance] then
		return
	end
	local visual = bind(instance)
	self.Cats[instance] = visual
	self.Janitor:Add(visual.Janitor, "Destroy", instance)
end

function CatHandler.Untrack(self: CatHandler, instance: Instance): ()
	self.Janitor:Remove(instance)
	self.Cats[instance] = nil
end

function CatHandler.Destroy(self: CatHandler): ()
	self.Janitor:Destroy()
	table.clear(self.Cats)
end

export type CatHandler = typeof(CatHandler) & { Janitor: any, Cats: { [Instance]: Visual } }
return CatHandler :: CatHandler
