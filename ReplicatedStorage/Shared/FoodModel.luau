--!strict
-- One disposable food model, normalized around its bottom rather than the imported world pivot.
-- Server surfaces, the carrying tray and UI previews share the same authored geometry.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local DisplayCustomers = require(_Shared.Configs.DisplayCustomers)
local VFX = require(_Shared.Configs.VFX)
local BurnConfig = require(_Shared.Configs.FoodBurn)
local FoodBurn = require(_Shared.FoodBurn)

--[[ Tables ]]--
local FoodModel = {}
FoodModel.__index = FoodModel

export type FoodModel = typeof(setmetatable(
	{} :: {
		Model: Model,
		Size: Vector3,
		Parts: { { Part: BasePart, Offset: CFrame, Color: Color3 } },
		BurnFade: number?,
		Janitor: any,
	},
	FoodModel
))

--[[ Private Functions ]]--
local function partReach(part: BasePart): Vector3
	local frame, size = part.CFrame, part.Size
	return (frame.RightVector:Abs() * size.X + frame.UpVector:Abs() * size.Y + frame.LookVector:Abs() * size.Z) / 2
end

--[[ Handling ]]--
function FoodModel.FindAsset(assetName: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	local folder = models and models:FindFirstChild("Cake")
	local source = folder and folder:FindFirstChild(assetName)
	return if source and source:IsA("Model") then source else nil
end

function FoodModel.new(assetName: string, parent: Instance, maxSize: Vector3, burnt: boolean?): FoodModel?
	local source = FoodModel.FindAsset(assetName)
	if not source then
		return nil
	end
	return FoodModel.FromSource(source, parent, maxSize, burnt)
end

-- Direct carry uses the same size normalization as dishes, including single authored mesh parts.
function FoodModel.FromSource(
	source: Instance,
	parent: Instance,
	maxSize: Vector3,
	burnt: boolean?,
	rotation: CFrame?
): FoodModel?
	local content = source:Clone()
	local clone: Model
	if content:IsA("Model") then
		clone = content
		clone.PrimaryPart = nil
	else
		clone = Instance.new("Model")
		clone.Name = source.Name
		content.Parent = clone
	end
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum
	local pieces: { BasePart } = {}
	for _, child in clone:GetDescendants() do
		if not child:IsA("BasePart") then
			continue
		end
		if rotation then
			child.CFrame = rotation * child.CFrame
		end
		local reach = partReach(child)
		minimum = minimum:Min(child.Position - reach)
		maximum = maximum:Max(child.Position + reach)
		pieces[#pieces + 1] = child
	end
	if #pieces == 0 then
		clone:Destroy()
		return nil
	end
	local size = maximum - minimum
	local scale = math.min(
		1,
		maxSize.X / math.max(size.X, 0.001),
		maxSize.Y / math.max(size.Y, 0.001),
		maxSize.Z / math.max(size.Z, 0.001)
	)
	local bottom = Vector3.new((minimum.X + maximum.X) / 2, minimum.Y, (minimum.Z + maximum.Z) / 2)
	local self = setmetatable({ Model = clone, Size = size * scale, Parts = {}, Janitor = Janitor.new() }, FoodModel)
	self.Janitor:Add(clone, "Destroy")
	for _, part in pieces do
		local offset = CFrame.new((part.Position - bottom) * scale) * part.CFrame.Rotation
		part.Size *= scale
		part.CFrame = offset
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		self.Parts[#self.Parts + 1] = { Part = part, Offset = offset, Color = part.Color }
	end
	clone.WorldPivot = CFrame.identity
	clone.Parent = parent
	if burnt then
		self:SetBurn(1)
	end
	return self
end

function FoodModel.ForItem(recipeId: string, kind: string, parent: Instance, maxSize: Vector3): FoodModel?
	if kind == "Leftover" then
		local source = Instance.new("Part")
		source.Name = "Leftover Pastry"
		source.Size = DisplayCustomers.PackageSize
		source.Color = DisplayCustomers.PackageColor
		source.Material = Enum.Material.SmoothPlastic
		local visual = FoodModel.FromSource(source, parent, maxSize)
		source:Destroy()
		return visual
	end
	local recipe = Recipes:Get(recipeId)
	if not recipe or not recipe.asset then
		return nil
	end
	-- The yellow pastry mesh is a neutral mixed batch; it is not shown as finished decorated food.
	local asset = if kind == "Dough" then "pastry" else recipe.asset
	local visual = FoodModel.new(asset, parent, maxSize, kind == "Burnt")
	if visual then
		visual.Model:SetAttribute("RecipeId", recipeId)
		visual.Model:SetAttribute("FoodKind", kind)
		-- The first real mesh follows SetCFrame; a Model's imported WorldPivot does not.
		-- UI copies receive the metadata too, but the client only tracks Workspace descendants.
		local entry = visual.Parts[1]
		if kind == "Dish" and entry then
			entry.Part:SetAttribute("RecipeId", recipeId)
			entry.Part:SetAttribute(VFX.RoleAttribute, "Food")
			entry.Part:SetAttribute(VFX.SizeAttribute, visual.Size)
			entry.Part:SetAttribute(VFX.OffsetAttribute, entry.Offset:Inverse() * CFrame.new(0, visual.Size.Y / 2, 0))
			entry.Part:AddTag(VFX.Tag)
		end
	end
	return visual
end

function FoodModel.SetCFrame(self: FoodModel, frame: CFrame): ()
	for _, entry in self.Parts do
		entry.Part.CFrame = frame * entry.Offset
	end
end

function FoodModel.SetBurn(self: FoodModel, fade: number): ()
	fade = math.round(math.clamp(fade, 0, 1) * BurnConfig.FadeSteps) / BurnConfig.FadeSteps
	if self.BurnFade == fade then
		return
	end
	self.BurnFade = fade
	for _, entry in self.Parts do
		local part = entry.Part
		if part:FindFirstChildWhichIsA("SurfaceAppearance") then
			part:SetAttribute(BurnConfig.FadeAttribute, fade)
			part:AddTag(BurnConfig.Tag)
		else
			part.Color = FoodBurn.Color(entry.Color, fade)
		end
	end
end

function FoodModel.Destroy(self: FoodModel): ()
	self.Janitor:Destroy()
end

return FoodModel
