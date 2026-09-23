--!strict
-- One active prompt's white outlines. Authored geometry and local animated copies stay untouched.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Base = require(ReplicatedStorage.Shared.Configs.Base)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Config = require(ReplicatedStorage.Shared.Configs.InteractionHighlight)
local Garden = require(ReplicatedStorage.Shared.Configs.Garden)
local Tables = require(ReplicatedStorage.Shared.Configs.TableMenus)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local InteractionHighlight = {}
InteractionHighlight.__index = InteractionHighlight

export type InteractionHighlight = typeof(setmetatable(
	{} :: {
		Janitor: any,
		Parts: any,
		Outlines: any,
		Root: Folder,
		Enabled: boolean,
		ResolvePart: (BasePart) -> BasePart,
	},
	InteractionHighlight
))

--[[ Private Functions ]]--
local function bakeryOf(part: Instance): Instance?
	local root = part
	while root.Parent and root.Parent.Name ~= Base.BakeriesFolderName do
		root = root.Parent
	end
	return if root.Parent then root else nil
end

local function childrenOf(instance: Instance?): { Instance }
	return if instance then instance:GetChildren() else {}
end

local function descendantsOf(instance: Instance?): { Instance }
	return if instance then instance:GetDescendants() else {}
end

local function appendMatchingChildren(parent: Instance, name: string, matches: { Instance }): ()
	for _, child in parent:GetChildren() do
		if child.Name ~= name then
			continue
		end

		table.insert(matches, child)
	end
end

-- Both entrance leaves are named Door; a highlight path can select several authored siblings.
local function resolveTargets(root: Instance, path: { string }): { Instance }
	local matches: { Instance } = { root }

	for _, name in path do
		local nextMatches: { Instance } = {}

		for _, parent in matches do
			appendMatchingChildren(parent, name, nextMatches)
		end

		matches = nextMatches
	end

	return matches
end

local function nearest(part: BasePart, candidates: { Instance }): Instance?
	local best: Instance? = nil
	local distance = math.huge
	for _, candidate in candidates do
		if not candidate:IsA("Model") and not candidate:IsA("BasePart") then
			continue
		end
		local visible = if candidate:IsA("BasePart")
			then candidate
			else candidate:FindFirstChildWhichIsA("BasePart", true)
		if not visible or visible.Transparency >= 1 then
			continue
		end
		local frame: CFrame, size: Vector3
		if candidate:IsA("Model") then
			frame, size = candidate:GetBoundingBox()
		else
			frame, size = candidate.CFrame, candidate.Size
		end
		local offset = frame:PointToObjectSpace(part.Position)
		local gap = (offset - offset:Max(-size / 2):Min(size / 2)).Magnitude
		if gap < distance then
			best, distance = candidate, gap
		end
	end
	return best
end

local function targets(part: BasePart): { Instance }
	local authored = Buildings.WorldModel(part)
	if authored then
		return { authored }
	end
	local bakery = bakeryOf(part)
	if not bakery then
		return { part }
	end
	local id = part:GetAttribute(Buildings.IdAttribute)
	local kindName = part:GetAttribute(Buildings.KindAttribute)
	if typeof(id) ~= "string" then
		return { part }
	end
	local kind = if typeof(kindName) == "string" then Buildings.Kinds[kindName] else nil
	local path: { string }? = Config.Paths[id] or (if kind then kind.PromptTarget else nil)
	if path then
		return resolveTargets(bakery, path)
	end
	local source = Garden.Sources[id]
	if source then
		if part:GetAttribute(Garden.AnimalActionAttribute) == "Harvest" then
			local food = {}
			local props = part.Parent and part.Parent.Parent
			for _, child in childrenOf(props) do
				if child:GetAttribute("GardenSourceId") == id then
					table.insert(food, child)
				end
			end
			return food
		end
		local garden = Buildings.ResolvePath(bakery, Config.GardenPath)
		local folder = garden and garden:FindFirstChild(source.Folder)
		return if folder then { folder } else {}
	end
	if kindName == "Table" then
		local tablePath = Tables.Paths[Buildings.GetIndex(id)]
		local holder = tablePath and Buildings.ResolvePath(bakery, tablePath)
		local candidates: { Instance } = {}
		for _, child in childrenOf(holder) do
			if child.Name == "Table" then
				candidates[#candidates + 1] = child
			end
		end
		local target = nearest(part, candidates)
		return if target then { target } else {}
	end
	if kindName == "Display" then
		local candidates: { Instance } = {}
		local counters = Buildings.ResolvePath(bakery, Config.DisplayPath)
		for _, child in descendantsOf(counters) do
			if child:IsA("Model") and child.Name:match("^Counter%d+$") then
				candidates[#candidates + 1] = child
			end
		end
		local ledges = Buildings.ResolvePath(bakery, Config.DisplayLedgePath)
		for _, child in childrenOf(ledges) do
			if Config.DisplayLedgeNames[child.Name] then
				candidates[#candidates + 1] = child
			end
		end
		local target = nearest(part, candidates)
		return if target then { target } else {}
	end
	if kindName == "RailOutput" then
		local buildings = part.Parent
		local index = math.max(1, Buildings.GetIndex(id))
		for _, child in childrenOf(buildings) do
			if child:GetAttribute(Buildings.IdAttribute) ~= "rail_cart" then
				continue
			end
			for _, cargo in child:GetChildren() do
				if cargo:GetAttribute("DeliverySlot") == index then
					return { cargo }
				end
			end
		end
		return {}
	end
	-- Spill prompts sit on a mesh inside the authored puddle model.
	if kindName == "Spill" and part.Parent and part.Parent:IsA("Model") then
		return { part.Parent }
	end
	return { part }
end

--[[ Handling ]]--
function InteractionHighlight.new(resolvePart: (BasePart) -> BasePart): InteractionHighlight
	local root = Instance.new("Folder")
	root.Name = "InteractionHighlights"
	root.Parent = workspace
	local self = setmetatable({
		Janitor = Janitor.new(),
		Parts = Janitor.new(),
		Outlines = Janitor.new(),
		Root = root,
		Enabled = false,
		ResolvePart = resolvePart,
	}, InteractionHighlight)
	self.Janitor:Add(root, "Destroy")
	self.Janitor:Add(self.Parts, "Destroy")
	self.Janitor:Add(self.Outlines, "Destroy")
	return self
end

function InteractionHighlight.Watch(self: InteractionHighlight, part: BasePart): ()
	local function refresh(): ()
		self.Outlines:Remove(part)
		local visible = self.ResolvePart(part)
		if
			not part:IsDescendantOf(workspace)
			or part.Transparency >= 1
			or visible.Transparency >= 1
			or visible.LocalTransparencyModifier >= 1
		then
			return
		end
		local outline = Instance.new("Highlight")
		outline.Name = "Interactable"
		outline.Adornee = visible
		outline.FillColor = Config.Color
		outline.OutlineColor = Config.Color
		outline.FillTransparency = Config.FillTransparency
		outline.OutlineTransparency = Config.OutlineTransparency
		outline.DepthMode = Config.DepthMode
		outline.Enabled = self.Enabled
		outline.Parent = self.Root
		self.Outlines:Add(outline, "Destroy", part)
	end
	self.Parts:Add(part:GetPropertyChangedSignal("Transparency"):Connect(refresh), "Disconnect")
	self.Parts:Add(part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(refresh), "Disconnect")
	self.Parts:Add(part.AncestryChanged:Connect(refresh), "Disconnect")
	refresh()
end

function InteractionHighlight.Show(self: InteractionHighlight, part: BasePart): ()
	self.Parts:Cleanup()
	self.Outlines:Cleanup()
	if part:GetAttribute(Garden.AnimalActionAttribute) == "Harvest" then
		local props = part.Parent and part.Parent.Parent
		if props then
			local function refresh(): ()
				self:Show(part)
			end
			self.Parts:Add(props.ChildAdded:Connect(refresh), "Disconnect")
			self.Parts:Add(props.ChildRemoved:Connect(refresh), "Disconnect")
		end
	end
	-- The cart rebuilds delivery models after pickup; the selected tray can keep the same prompt.
	if part:GetAttribute(Buildings.KindAttribute) == "RailOutput" then
		local cart = part.Parent and part.Parent:FindFirstChild("rail_cart")
		if cart then
			local function refresh(): ()
				self:Show(part)
			end
			self.Parts:Add(cart.ChildAdded:Connect(refresh), "Disconnect")
			self.Parts:Add(cart.ChildRemoved:Connect(refresh), "Disconnect")
		end
	end
	local seen: { [BasePart]: boolean } = {}
	local function watch(instance: Instance): ()
		if not instance:IsA("BasePart") or seen[instance] then
			return
		end
		seen[instance] = true
		self:Watch(instance)
	end
	for _, target in targets(part) do
		watch(target)
		for _, child in target:GetDescendants() do
			watch(child)
		end
		self.Parts:Add(target.DescendantAdded:Connect(watch), "Disconnect")
	end
end

function InteractionHighlight.SetEnabled(self: InteractionHighlight, enabled: boolean): ()
	self.Enabled = enabled
	for _, outline in self.Root:GetChildren() do
		if outline:IsA("Highlight") then
			outline.Enabled = enabled
		end
	end
end

function InteractionHighlight.Hide(self: InteractionHighlight): ()
	self.Parts:Cleanup()
	self.Outlines:Cleanup()
end

function InteractionHighlight.Destroy(self: InteractionHighlight): ()
	self.Janitor:Destroy()
end

return InteractionHighlight
