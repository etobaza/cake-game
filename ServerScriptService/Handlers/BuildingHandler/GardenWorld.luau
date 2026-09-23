--!strict
-- Owns the authored source variants and stock models for one claimed greenhouse.
-- UpgradeViewHandler leaves these folders alone; teardown restores every authored property.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Config = require(_Shared.Configs.Garden)
local Buildings = require(_Shared.Configs.Buildings)
local AnimalCare = require(_Shared.AnimalCare)
local Motion = require(_Shared.Configs.AmbientMotion)
local CarryModel = require(_Shared.CarryModel)
local FoodModel = require(_Shared.FoodModel)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Constants ]]--
local FRUIT_MESHES = {
	["121967715738423"] = true,
	["128318190733927"] = true,
	["101229812640132"] = true,
	["108047708452402"] = true,
	["128859739946307"] = true,
	["85439120044613"] = true,
	["70428964020976"] = true,
	["77180463972586"] = true,
	["139764369320072"] = true,
}

--[[ Tables ]]--
local GardenWorld = {}
GardenWorld.__index = GardenWorld

export type GardenWorld = typeof(setmetatable(
	{} :: {
		Data: any,
		Root: Instance,
		Records: { any },
		Janitor: any,
	},
	GardenWorld
))

--[[ Private Functions ]]--
local function show(entry: any, visible: boolean): ()
	local part = entry.Part
	part.Transparency = if visible then entry.Transparency else 1
	part.CanCollide = visible and entry.CanCollide
	part.CanQuery = visible and entry.CanQuery
end

local function publishMotion(part: BasePart, kind: string, variant: Instance, janitor: any, center: Vector3?): ()
	local oldKind, oldCenter = part:GetAttribute(Motion.KindAttribute), part:GetAttribute(Motion.CenterAttribute)
	local hadTag = part:HasTag(Motion.Tag)
	part:SetAttribute(Motion.KindAttribute, kind)
	if center then
		part:SetAttribute(Motion.CenterAttribute, center)
	elseif kind == "Bee" then
		local hive = variant:FindFirstChild("Hive")
		local hivePart = hive and hive:FindFirstChildWhichIsA("BasePart", true)
		if hivePart then
			part:SetAttribute(
				Motion.CenterAttribute,
				Vector3.new(hivePart.Position.X, part.Position.Y, hivePart.Position.Z)
			)
		end
	end
	part:AddTag(Motion.Tag)
	janitor:Add(function(): ()
		if not hadTag then
			part:RemoveTag(Motion.Tag)
		end
		part:SetAttribute(Motion.KindAttribute, oldKind)
		part:SetAttribute(Motion.CenterAttribute, oldCenter)
	end, true)
end

local function animalCenter(part: BasePart, folder: Instance, source: Config.Source): Vector3
	local closest: BasePart? = nil
	local distance = math.huge
	for _, variant in folder:GetChildren() do
		if variant.Name == source.DryVariant or variant.Name:match("^BuildPlaceholder") then
			continue
		end
		for _, candidate in variant:GetDescendants() do
			if not candidate:IsA("MeshPart") or not part:IsA("MeshPart") or candidate.MeshId ~= part.MeshId then
				continue
			end
			local offset = (candidate.Position - part.Position).Magnitude
			if offset < distance then
				closest, distance = candidate, offset
			end
		end
	end
	return if closest then closest.Position else part.Position
end

local function collect(folder: Instance, janitor: any, source: Config.Source): { any }
	local entries = {}
	for _, variant in folder:GetChildren() do
		for _, part in variant:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			local mesh = if part:IsA("MeshPart") then part.MeshId:match("%d+") else nil
			local motionKind = mesh and Motion.MeshKinds[mesh]
			if
				not motionKind
				and source.Care == "Plant"
				and mesh
				and not FRUIT_MESHES[mesh]
				and not variant.Name:match("^BuildPlaceholder")
			then
				motionKind = "Plant"
			end
			if motionKind then
				local center = if motionKind == "Plant" and source.Produce == "strawberry"
					then part.Position - Vector3.yAxis * part.Size.Y / 2
					else nil
				-- Both authored skins must sample the same animation clock, despite their small mesh offset.
				if source.Care == "Animal" and (motionKind == "Cow" or motionKind == "Chicken") then
					center = animalCenter(part, folder, source)
				end
				publishMotion(part, motionKind, variant, janitor, center)
			end
			entries[#entries + 1] = {
				Part = part,
				Variant = variant.Name,
				Fruit = mesh and FRUIT_MESHES[mesh],
				Transparency = part.Transparency,
				CanCollide = part.CanCollide,
				CanQuery = part.CanQuery,
			}
		end
	end
	janitor:Add(function()
		for _, entry in entries do
			if entry.Part.Parent then
				show(entry, true)
			end
		end
	end, true)
	return entries
end

local function stockFrame(record: any, index: number): CFrame
	return record.Frames[index]
end

local function treeFrames(entries: { any }): { CFrame }?
	local fruit = nil
	for _, entry in entries do
		if entry.Fruit and not entry.Variant:match("^BuildPlaceholder") then
			fruit = entry
			break
		end
	end
	if not fruit then
		return nil
	end
	local tree: BasePart? = nil
	for _, entry in entries do
		if entry.Fruit or entry.Variant ~= fruit.Variant then
			continue
		end
		if not tree or entry.Part.Size.Y > tree.Size.Y then
			tree = entry.Part
		end
	end
	if not tree then
		return nil
	end
	local frames = {}
	for index = 1, Config.Capacity do
		local offset = Config.TreeProduceOffsets[index]
		if not offset then
			return nil
		end
		local position = tree.CFrame:PointToWorldSpace(Vector3.new(offset.X * tree.Size.X, 0, offset.Z * tree.Size.Z))
		frames[index] = CFrame.new(position.X, fruit.Part.Position.Y + offset.Y, position.Z) * tree.CFrame.Rotation
	end
	return frames
end

local function stockVisual(record: any, frame: CFrame): FoodModel.FoodModel?
	if record.Source.Kind == "Tree" then
		for _, entry in record.Entries do
			if not entry.Fruit or entry.Variant:match("^BuildPlaceholder") then
				continue
			end
			-- Tree fruit keeps its authored size and world orientation, independent of tray limits.
			local part = entry.Part
			local extent = part.Size.Magnitude
			local visual = FoodModel.FromSource(
				part,
				record.Parent,
				Vector3.new(extent, extent, extent),
				false,
				frame.Rotation:Inverse()
			)
			if not visual then
				continue
			end
			for _, piece in visual.Parts do
				piece.Part.Transparency = entry.Transparency
			end
			visual.Model:SetAttribute("ItemKind", "Ingredient")
			visual.Model:SetAttribute("ItemId", record.Source.Produce)
			return visual
		end
	end
	return CarryModel.new({ Kind = "Ingredient", Id = record.Source.Produce }, record.Parent)
end

local function attachStrawberry(record: any, visual: FoodModel.FoodModel, frame: CFrame, index: number): ()
	local plant: BasePart? = record.StockPlant
	if not plant then
		return
	end
	local center = plant.Position - Vector3.yAxis * plant.Size.Y / 2
	local origin = plant.CFrame:PointToWorldSpace(Config.StrawberryStemRoot)
	local tip = frame:PointToWorldSpace(Vector3.new(0, visual.Size.Y * 0.86, 0))
	local control = (origin + tip) / 2 + Vector3.yAxis * Config.StrawberryStemLift
	local stems = Instance.new("Model")
	stems.Name = `StrawberryStem{index}`
	stems.Parent = record.Parent
	record.StockJanitor:Add(stems, "Destroy")
	local previous = origin
	for segment = 1, Config.StrawberryStemSegments do
		local t = segment / Config.StrawberryStemSegments
		local point = origin * (1 - t) ^ 2 + control * (2 * (1 - t) * t) + tip * t ^ 2
		local part = Instance.new("Part")
		part.Name = `Stem{segment}`
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(
			(point - previous).Magnitude + Config.StrawberryStemThickness,
			Config.StrawberryStemThickness,
			Config.StrawberryStemThickness
		)
		-- Cylinders run along local X. Slight overlap keeps segment joints closed.
		part.CFrame = CFrame.lookAt((previous + point) / 2, point) * CFrame.Angles(0, math.pi / 2, 0)
		part.Color = Config.StrawberryStemColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.CastShadow = false
		part.Parent = stems
		publishMotion(part, "Plant", record.Folder, record.StockJanitor, center)
		previous = point
	end
	for _, entry in visual.Parts do
		publishMotion(entry.Part, "Plant", record.Folder, record.StockJanitor, center)
	end
end

local function paint(record: any, owned: boolean, state: any, day: number): ()
	local stock = if state then state.Stock else 0
	local healthy = state and (state.CareRemaining > 0 or state.CleanDay == day)
	local live = healthy or record.Source.Care == "Hive" or (record.Source.Kind == "Tree" and stock > 0)
	local signature = `{owned}:{live}:{stock}`
	if record.Signature == signature then
		return
	end
	local hasDry = record.Folder:FindFirstChild("Upgrade2") ~= nil
	local dryVariant = record.Source.DryVariant or "Upgrade2"
	for _, entry in record.Entries do
		local placeholder = entry.Variant:match("^BuildPlaceholder") ~= nil
		local visible = if placeholder then not owned else owned
		if not placeholder and hasDry then
			visible = visible and (if entry.Variant == dryVariant then not live else live)
		end
		-- Runtime stock copies replace the original fruit; tree copies fill separate branches.
		if entry.Fruit then
			visible = false
		end
		show(entry, visible)
	end
	for _, entry in record.OutputEntries do
		-- Keep the artist's ingredient as an Edit-mode preview; runtime stock owns the live item.
		show(entry, owned and entry.Variant ~= "Preview")
	end
	record.StockJanitor:Cleanup()
	if owned then
		for index = 1, stock do
			local frame = stockFrame(record, index)
			local visual = stockVisual(record, frame)
			if not visual then
				continue
			end
			visual.Model:SetAttribute("GardenSourceId", record.Id)
			-- FoodModel pivots at the bottom; tree placement targets the fruit's center.
			if record.CenteredStock then
				frame *= CFrame.new(0, -visual.Size.Y / 2, 0)
			end
			visual:SetCFrame(frame)
			record.StockJanitor:Add(visual, "Destroy")
			attachStrawberry(record, visual, frame, index)
		end
	end
	record.Signature = signature
end

local function animateCare(record: any, owned: boolean, state: any, day: number, now: number): ()
	if not owned or not state or record.Source.Care ~= "Animal" then
		return
	end
	local clean = AnimalCare.Brushing(state, day, now)
	local dirtyVisible = clean < Config.DirtyAppearanceThreshold
	for _, entry in record.Entries do
		local kind = entry.Part:GetAttribute(Motion.KindAttribute)
		if kind ~= "Cow" and kind ~= "Chicken" then
			continue
		end
		local dirty = entry.Variant == record.Source.DryVariant
		-- Each skin includes the whole animal. Fading one over the other duplicates the silhouette.
		show(entry, dirty == dirtyVisible)
	end
end

--[[ Handling ]]--
function GardenWorld.new(
	root: Instance,
	parent: Instance,
	data: any,
	template: Instance,
	transform: CFrame
): GardenWorld
	local self = setmetatable({ Data = data, Root = root, Records = {}, Janitor = Janitor.new() }, GardenWorld)
	local floor = root:FindFirstChild("1ndFloor")
	local garden = floor and floor:FindFirstChild("Garden")
	local upgrades = garden and garden:FindFirstChild("Upgrades")
	local anchors = template:FindFirstChild("Anchors")
	for id, source in Config.Sources do
		local folder = upgrades and upgrades:FindFirstChild(source.Folder)
		local anchor = anchors and anchors:FindFirstChild(id)
		if not folder or not anchor or not anchor:IsA("BasePart") then
			continue
		end
		local frames = {}
		for index = 1, source.Capacity or Config.Capacity do
			local point = anchor:FindFirstChild(`GardenProduce{index}`)
			frames[index] = transform
				* (
					if point and point:IsA("Attachment")
						then point.WorldCFrame
						else anchor.CFrame * CFrame.new((index - 2.5) * 1.2, 0.25, -2)
				)
		end
		local carePoint = anchor:FindFirstChild("GardenCare")
		local careFrame = if carePoint and carePoint:IsA("Attachment") then transform * carePoint.WorldCFrame else nil
		local stockJanitor, careJanitor = Janitor.new(), Janitor.new()
		self.Janitor:Add(stockJanitor, "Destroy")
		self.Janitor:Add(careJanitor, "Destroy")
		local entries = collect(folder, self.Janitor, source)
		local output = source.OutputPath and Buildings.ResolvePath(root, source.OutputPath)
		local outputEntries = if output then collect(output, self.Janitor, source) else {}
		local stockPlant: BasePart? = nil
		if source.Produce == "strawberry" then
			for _, entry in entries do
				if entry.Fruit or entry.Variant:match("^BuildPlaceholder") then
					continue
				end
				if not stockPlant or entry.Part.Size.Y > stockPlant.Size.Y then
					stockPlant = entry.Part
				end
			end
		end
		local branchFrames = if source.Kind == "Tree" then treeFrames(entries) else nil
		self.Records[#self.Records + 1] = {
			Id = id,
			Source = source,
			Folder = folder,
			Frames = branchFrames or frames,
			CenteredStock = branchFrames ~= nil,
			CareFrame = careFrame,
			StockPlant = stockPlant,
			Parent = parent,
			Entries = entries,
			OutputEntries = outputEntries,
			StockJanitor = stockJanitor,
			CareJanitor = careJanitor,
		}
	end
	self:Update(0, workspace:GetServerTimeNow())
	return self
end

function GardenWorld.Update(self: GardenWorld, _deltaTime: number, now: number): ()
	local cloud = self.Data.Cloud
	for _, record in self.Records do
		local state = cloud.Garden[record.Source.Group][record.Id]
		local owned = (cloud.Base.Upgrades[record.Source.Upgrade] or 0) > 0
		paint(record, owned, state, cloud.Day)
		animateCare(record, owned, state, cloud.Day, now)
	end
end

function GardenWorld.Destroy(self: GardenWorld): ()
	self.Janitor:Destroy()
end

return GardenWorld
