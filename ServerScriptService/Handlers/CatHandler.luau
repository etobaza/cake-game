--!strict
-- Daily cafe cats, validated care and exclusive customer adoption reservations.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local BaseHandler = require(script.Parent.BaseHandler)
local DataHandler = require(script.Parent.DataHandler)
local DayCycleHandler = require(script.Parent.DayCycleHandler)
local InventoryHandler = require(script.Parent.InventoryHandler)
local TickHandler = require(script.Parent.TickHandler)
local UpgradeHandler = require(script.Parent.UpgradeHandler)
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.Cats)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Sanitize = require(ReplicatedStorage.Shared.Sanitize)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "CatHandler" })

type Cat = {
	Model: Model,
	Part: BasePart,
	Approach: Vector3,
	Pose: string,
	Slot: string,
	Petted: boolean,
	Fed: boolean,
	NextPet: number,
	PetEnds: number?,
	PetCharacter: Model?,
	Customer: string?,
	ReservedUntil: number?,
}
type Base = {
	Root: Folder,
	Folder: Folder,
	Janitor: any,
	Cats: { [string]: Cat },
	Day: number,
	Level: number,
	Chance: number,
}
type SavedCat = { Variant: number, Pose: string, Seed: number, Petted: boolean, Fed: boolean, Adopted: boolean }
local CatHandler = {
	dependencies = {
		"BaseHandler",
		"DataHandler",
		"DayCycleHandler",
		"InventoryHandler",
		"UpgradeViewHandler",
		"TickHandler",
	},
}

local function active(data: any): boolean
	return data ~= nil and (data.Session.Day.Phase == "Prep" or data.Session.Day.Phase == "Shift")
end

local function nearby(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil
		and root:IsA("BasePart")
		and humanoid ~= nil
		and humanoid.Health > 0
		and (root.Position - part.Position).Magnitude <= Config.InteractDistance
end

local function burst(player: Player, cat: Cat): ()
	Bus.VFX.Burst:Fire("Happy", cat.Part, cat.Part.CFrame, player.UserId, workspace:GetServerTimeNow())
end

local function habitat(root: Folder, name: string): BasePart?
	local floor = root:FindFirstChild("1ndFloor")
	local cafe = floor and floor:FindFirstChild("Cafe")
	local upgrades = cafe and cafe:FindFirstChild("Upgrades")
	local folder = upgrades and upgrades:FindFirstChild("CatCafe")
	local model = folder and folder:FindFirstChild(name, true)
	return if model then model:FindFirstChildWhichIsA("BasePart", true) else nil
end

function CatHandler.OnInit(self: CatHandler): ()
	self.Bases = {}
	self.Sources = {}
	self.Janitor = Janitor.new()
	self.Random = Random.new()
	self.Templates = Instance.new("Folder")
	self.Templates.Name = "CafeCatTemplates"
	self.Templates.Parent = ServerStorage
	self.Janitor:Add(self.Templates, "Destroy")
	local assets = workspace:FindFirstChild("Asset")
	for _, model in if assets then assets:GetChildren() else {} do
		if model.Name == "cat" and model:IsA("Model") and model:FindFirstChildWhichIsA("MeshPart", true) then
			local template = model:Clone()
			template.Parent = self.Templates
			table.insert(self.Sources, template)
		end
	end
	table.sort(self.Sources, function(a: Model, b: Model): boolean
		return (a:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart).MeshId
			< (b:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart).MeshId
	end)
	if #self.Sources == 0 then
		Logger:Warn("Workspace.Asset.cat templates are missing")
	end
end

function CatHandler.OnStart(self: CatHandler): ()
	self.Janitor:Add(
		BaseHandler.BaseReady:Connect(function(player: Player, root: Folder)
			self:Bind(player, root)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		BaseHandler.BaseRemoving:Connect(function(player: Player)
			self:Unbind(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player)
			self:Unbind(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		UpgradeHandler.StatsChanged:Connect(function(player: Player)
			self:Refresh(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		DayCycleHandler.DayStarted:Connect(function(player: Player)
			self:Refresh(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Bus.Cafe.CatInteract.OnServerEvent:Connect(function(player: Player, rawId: any)
			local id = Sanitize.Id(rawId)
			if id then
				self:Interact(player, id)
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		TickHandler.Tick:Connect(function()
			self:Update(workspace:GetServerTimeNow())
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		local root = BaseHandler:GetBase(player)
		if root then
			self:Bind(player, root)
		end
	end
end

function CatHandler.Bind(self: CatHandler, player: Player, root: Folder): ()
	local current = self.Bases[player]
	if current and current.Root == root then
		self:Refresh(player)
		return
	end
	self:Unbind(player)
	local janitor = Janitor.new()
	local folder = Instance.new("Folder")
	folder.Name = Config.FolderName
	folder.Parent = root
	janitor:Add(folder, "Destroy")
	self.Bases[player] = {
		Root = root,
		Folder = folder,
		Janitor = janitor,
		Cats = {},
		Day = -1,
		Level = -1,
		Chance = Config.AdoptChance,
	}
	self:Refresh(player)
end

function CatHandler.Refresh(self: CatHandler, player: Player): ()
	local base = self.Bases[player]
	local data = DataHandler:GetData(player)
	if not base or not data or BaseHandler:GetBase(player) ~= base.Root then
		return
	end
	local level = math.clamp(data.Cloud.Base.Upgrades[Config.UpgradeId] or 0, 0, #Config.Counts)
	local day = data.Cloud.Day
	if base.Level == level and base.Day == day then
		return
	end
	base.Level, base.Day, base.Chance = level, day, Config.AdoptChance
	base.Folder:ClearAllChildren()
	table.clear(base.Cats)
	if level == 0 or #self.Sources == 0 then
		return
	end
	local saved = data.Cloud.CatCafe
	if saved and saved.Day == day and saved.Level == level then
		for _, entry in saved.Cats do
			if entry.Petted then
				base.Chance = math.min(Config.MaxAdoptChance, base.Chance + Config.PetAdoptBonus)
			end
		end
		for _, slot in Config.Slots do
			local entry = saved.Cats[slot.Id]
			if entry and not entry.Adopted and slot.Level <= level then
				self:Spawn(player, base, slot, entry)
			end
		end
		return
	end
	-- Lazy initialization also handles profiles created before CatCafe was introduced.
	data.Cloud.CatCafe = { Day = day, Level = level, Cats = {} }
	local slots = {}
	for _, slot in Config.Slots do
		if slot.Level <= level and habitat(base.Root, slot.Habitat) then
			table.insert(slots, slot)
		end
	end
	local count = Config.Counts[level]
	local wanted = math.min(#slots, self.Random:NextInteger(count.Min, count.Max))
	for _ = 1, wanted do
		local slot = table.remove(slots, self.Random:NextInteger(1, #slots))
		self:Spawn(player, base, slot)
	end
end

function CatHandler.Spawn(self: CatHandler, player: Player, base: Base, slot: any, saved: SavedCat?): ()
	local support = habitat(base.Root, slot.Habitat)
	if not support then
		return
	end
	local variant = if saved then saved.Variant else self.Random:NextInteger(1, #self.Sources)
	local source = self.Sources[variant]
	local model = source:Clone()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local id = HttpService:GenerateGUID(false)
	model.Name = `Cat_{slot.Id}`
	for _, child in model:GetDescendants() do
		if
			child:IsA("LuaSourceContainer")
			or child:IsA("AnimationController")
			or child.Name == "AnimSaves"
			or child.Name == "InitialPoses"
		then
			child:Destroy()
		elseif child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide, child.CanTouch, child.CanQuery = false, false, false
		end
	end
	local part = model:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart
	model.PrimaryPart = part
	model:ScaleTo(model:GetScale() * Config.Length / part.Size.X)
	-- Imported mesh faces -X and is already upright; discard the import model's rotated pivot.
	local bottom = support.CFrame * CFrame.new(0, -support.Size.Y / 2, 0)
	local position = bottom:PointToWorldSpace(slot.Offset)
	local frame = CFrame.new(position) * support.CFrame.Rotation * CFrame.Angles(0, math.rad(slot.Yaw), 0)
	part.CFrame = frame * CFrame.new(0, part.Size.Y / 2, 0)
	local pose = if saved then saved.Pose else slot.Pose
	if pose == "Rest" then
		pose = if self.Random:NextNumber() < 0.5 then "Lay" else "Sit"
	end
	local state: SavedCat = saved
		or {
			Variant = variant,
			Pose = pose,
			Seed = self.Random:NextNumber(0, 100),
			Petted = false,
			Fed = false,
			Adopted = false,
		}
	local data = DataHandler:GetData(player)
	if data then
		data.Cloud.CatCafe.Cats[slot.Id] = {
			Variant = state.Variant,
			Pose = state.Pose,
			Seed = state.Seed,
			Petted = state.Petted,
			Fed = state.Fed,
			Adopted = state.Adopted,
		}
	end
	model:SetAttribute("CatId", id)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("CatSlot", slot.Id)
	model:SetAttribute("CatPose", if state.Fed then "Drink" else pose)
	model:SetAttribute("CatSeed", state.Seed)
	model:SetAttribute("CatFed", state.Fed)
	model:SetAttribute("CatReserved", false)
	model:SetAttribute("CatPetUntil", 0)
	model.Parent = base.Folder
	local tree = habitat(base.Root, "CatHabitatOne") :: BasePart
	local ground = tree.Position.Y - tree.Size.Y / 2
	local approach = position + tree.CFrame:VectorToWorldSpace(Vector3.new(-4, 0, 0))
	base.Cats[id] = {
		Model = model,
		Part = part,
		Approach = Vector3.new(approach.X, ground, approach.Z),
		Pose = pose,
		Slot = slot.Id,
		Petted = state.Petted,
		Fed = state.Fed,
		NextPet = 0,
	}
	model:AddTag(Config.Tag)
end

function CatHandler.Interact(self: CatHandler, player: Player, id: string): boolean
	local base = self.Bases[player]
	local cat = base and base.Cats[id]
	local data = DataHandler:GetData(player)
	local now = workspace:GetServerTimeNow()
	if
		not base
		or not cat
		or not data
		or not cat.Model.Parent
		or not active(data)
		or BaseHandler:GetBase(player) ~= base.Root
		or cat.Customer
		or cat.PetEnds
		or now < cat.NextPet
		or not nearby(player, cat.Part)
	then
		return false
	end
	local held = InventoryHandler:Peek(player)
	if held then
		if held.Kind ~= "Ingredient" or held.Id ~= "milk" or cat.Slot ~= "Play" or cat.Fed then
			return false
		end
		InventoryHandler:Pop(player)
		cat.Fed = true
		data.Cloud.CatCafe.Cats[cat.Slot].Fed = true
		cat.Model:SetAttribute("CatFed", true)
		cat.Model:SetAttribute("CatPose", "Drink")
		burst(player, cat)
		return true
	end
	cat.NextPet = now + Config.PetCooldown
	cat.PetEnds, cat.PetCharacter = now + Config.PetSeconds, player.Character
	cat.Model:SetAttribute("CatPetUntil", cat.PetEnds)
	Bus.Player.PlayAction:FireClient(player, "PetCat")
	return true
end

function CatHandler.Update(self: CatHandler, now: number): ()
	for player, base in self.Bases do
		for _, cat in base.Cats do
			if cat.PetEnds then
				local valid = cat.PetCharacter == player.Character
					and active(DataHandler:GetData(player))
					and nearby(player, cat.Part)
					and InventoryHandler:Peek(player) == nil
				if not valid or now >= cat.PetEnds then
					cat.PetEnds, cat.PetCharacter = nil, nil
					cat.Model:SetAttribute("CatPetUntil", 0)
					if valid then
						if not cat.Petted then
							base.Chance = math.min(Config.MaxAdoptChance, base.Chance + Config.PetAdoptBonus)
						end
						cat.Petted = true
						local data = DataHandler:GetData(player)
						if data then
							data.Cloud.CatCafe.Cats[cat.Slot].Petted = true
						end
						burst(player, cat)
					end
				end
			end
			if cat.ReservedUntil and now >= cat.ReservedUntil then
				cat.Customer, cat.ReservedUntil = nil, nil
				cat.Model:SetAttribute("CatReserved", false)
			end
		end
	end
end

function CatHandler.Reserve(self: CatHandler, player: Player, customerId: string): string?
	local base = self.Bases[player]
	local data = DataHandler:GetData(player)
	if not base or not data or data.Session.Day.Phase ~= "Shift" or self.Random:NextNumber() >= base.Chance then
		return nil
	end
	for _, cat in base.Cats do
		if cat.Customer == customerId then
			return nil
		end
	end
	for id, cat in base.Cats do
		if not cat.Customer and not cat.PetEnds and cat.Model.Parent then
			cat.Customer, cat.ReservedUntil = customerId, workspace:GetServerTimeNow() + Config.AdoptTimeout
			cat.Model:SetAttribute("CatReserved", true)
			return id
		end
	end
	return nil
end

function CatHandler.GetReserved(self: CatHandler, player: Player, id: string, customerId: string): Cat?
	local base = self.Bases[player]
	local cat = base and base.Cats[id]
	return if cat
			and cat.Customer == customerId
			and cat.Model.Parent
			and cat.ReservedUntil
			and workspace:GetServerTimeNow() < cat.ReservedUntil
			and base
			and BaseHandler:GetBase(player) == base.Root
		then cat
		else nil
end

function CatHandler.Release(self: CatHandler, player: Player, customerId: string): ()
	local base = self.Bases[player]
	if not base then
		return
	end
	for _, cat in base.Cats do
		if cat.Customer ~= customerId then
			continue
		end
		cat.Customer, cat.ReservedUntil = nil, nil
		cat.Model:SetAttribute("CatReserved", false)
	end
end

function CatHandler.Complete(self: CatHandler, player: Player, id: string, customerId: string): boolean
	local cat = self:GetReserved(player, id, customerId)
	local data = DataHandler:GetData(player)
	if not cat or not data or (data.Session.Day.Phase ~= "Shift" and data.Session.Day.Phase ~= "Closing") then
		return false
	end
	-- Consume before awarding: repeated callbacks and stale customer IDs cannot pay twice.
	data.Cloud.CatCafe.Cats[cat.Slot].Adopted = true
	self.Bases[player].Cats[id] = nil
	-- The cat is destroyed right after, so the burst plays at its frame with no anchor instance.
	Bus.VFX.Burst:Fire("Happy", nil :: any, cat.Part.CFrame, player.UserId, workspace:GetServerTimeNow())
	cat.Model:Destroy()
	DayCycleHandler:AddResult(player, Config.AdoptReward, 0, 0, 0)
	Bus.Progress.RewardGranted:FireClient(player, "A cat found a home!")
	return true
end

function CatHandler.Unbind(self: CatHandler, player: Player): ()
	local base = self.Bases[player]
	if not base then
		return
	end
	self.Bases[player] = nil
	base.Janitor:Destroy()
end

function CatHandler.Destroy(self: CatHandler): ()
	for player in self.Bases do
		self:Unbind(player)
	end
	self.Janitor:Destroy()
	table.clear(self.Sources)
end

export type CatHandler = typeof(CatHandler) & {
	Bases: { [Player]: Base },
	Sources: { Model },
	Random: Random,
	Templates: Folder,
	Janitor: any,
}
return CatHandler :: CatHandler
