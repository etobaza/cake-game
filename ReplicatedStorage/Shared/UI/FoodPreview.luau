--!strict
-- Clones the authored viewport into an item icon. UIHandler supplies the screen template.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]
--
local Config = require(ReplicatedStorage.Shared.Configs.FoodPresentation)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local CarryModel = require(ReplicatedStorage.Shared.CarryModel)
local FoodModel = require(ReplicatedStorage.Shared.FoodModel)
local GameTypes = require(ReplicatedStorage.Shared.GameTypes)
local Ingredients = require(ReplicatedStorage.Shared.Configs.Registries.Ingredients)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(ReplicatedStorage.Shared.Configs.Registries.Recipes)

--[[ Tables ]]
--
local FoodPreview = {}
local template: ViewportFrame? = nil
local previews: { [ImageLabel]: { Key: string, Janitor: any } } = {}

--[[ Private Functions ]]
--
local function show(
	icon: ImageLabel,
	key: string,
	fallback: string,
	createVisual: (WorldModel) -> FoodModel.FoodModel?
): ()
	if previews[icon] and previews[icon].Key == key then
		return
	end
	FoodPreview.Clear(icon)
	icon.Image = fallback
	if not template then
		return
	end
	local viewport = template:Clone()
	local world = viewport:FindFirstChild("FoodWorld")
	if not world or not world:IsA("WorldModel") then
		viewport:Destroy()
		print("[FoodPreview] Template needs FoodWorld")
		return
	end
	-- Cameras do not replicate with StarterGui. The client owns this rendering resource;
	-- the viewport, its square constraint and WorldModel still come from the authored layout.
	local camera = viewport:FindFirstChildWhichIsA("Camera") or Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = Config.PreviewFieldOfView
	camera.Parent = viewport
	local visual = createVisual(world)
	if not visual then
		viewport:Destroy()
		return
	end
	local janitor = Janitor.new()
	janitor:Add(viewport, "Destroy")
	janitor:Add(visual, "Destroy")
	previews[icon] = { Key = key, Janitor = janitor }
	janitor:Add(
		icon.Destroying:Connect(function()
			FoodPreview.Clear(icon)
		end),
		"Disconnect"
	)
	local center = Vector3.new(0, visual.Size.Y / 2, 0)
	-- A bounding sphere remains inside the square viewport from every viewing angle.
	local distance = visual.Size.Magnitude / (2 * math.sin(math.rad(camera.FieldOfView / 2))) * 1.08
	camera.CFrame = CFrame.lookAt(center + Vector3.new(1, 0.9, 1.5).Unit * distance, center)
	viewport.CurrentCamera = camera
	viewport.Name = "FoodPreview"
	viewport.ZIndex = icon.ZIndex
	viewport.Visible = true
	icon.ImageTransparency = 1
	viewport.Parent = icon
end

--[[ Handling ]]
--
function FoodPreview.SetTemplate(source: Instance?): ()
	assert(source and source:IsA("ViewportFrame"), "[FoodPreview] Authored FoodPreviewTemplate is missing")
	template = source
end

function FoodPreview.Clear(icon: ImageLabel): ()
	local old = previews[icon]
	previews[icon] = nil
	if old then
		old.Janitor:Destroy()
	end
	icon.ImageTransparency = 0
end

function FoodPreview.Show(icon: ImageLabel, recipe: Recipes.RecipeEntry, kind: string?): ()
	local foodKind = kind or "Dish"
	show(icon, `{recipe.id}:{foodKind}`, Recipes:GetIcon(recipe), function(world: WorldModel): FoodModel.FoodModel?
		return FoodModel.ForItem(recipe.id, foodKind, world, Vector3.new(3, 3, 3))
	end)
end

function FoodPreview.ShowIngredient(icon: ImageLabel, ingredientId: string): ()
	local ingredient = Ingredients:Get(ingredientId)
	show(
		icon,
		`{ingredientId}:Ingredient`,
		if ingredient then ingredient.icon or "" else "",
		function(world: WorldModel): FoodModel.FoodModel?
			return CarryModel.new({ Kind = "Ingredient", Id = ingredientId }, world)
		end
	)
end

function FoodPreview.ShowTool(icon: ImageLabel, toolId: string): ()
	local kind = Buildings.KindForTool(toolId)
	show(icon, `{toolId}:Tool`, if kind then kind.Icon or "" else "", function(world: WorldModel): FoodModel.FoodModel?
		local asset = kind and (kind.HeldAsset or (kind.Furniture and kind.Furniture.Asset))
		local source = asset and Buildings.FindAsset(asset)
		return if source then FoodModel.FromSource(source, world, Vector3.new(3, 3, 3)) else nil
	end)
end

-- All carried item kinds share one dispatch, including fuel and leftovers without a recipe.
function FoodPreview.ShowItem(icon: ImageLabel, item: GameTypes.ItemStack?): ()
	if not item then
		FoodPreview.Clear(icon)
		icon.Image = ""
	elseif item.Kind == "Tool" then
		FoodPreview.ShowTool(icon, item.Id)
	elseif item.Kind == "Ingredient" then
		FoodPreview.ShowIngredient(icon, item.Id)
	elseif item.Kind == "Fuel" then
		show(icon, `{item.Id}:Fuel`, "", function(world: WorldModel): FoodModel.FoodModel?
			return CarryModel.new({ Kind = "Fuel", Id = item.Id }, world)
		end)
	else
		local recipe = Recipes:Get(item.Id)
		show(
			icon,
			`{item.Id}:{item.Kind}`,
			if recipe then Recipes:GetIcon(recipe) else "",
			function(world: WorldModel): FoodModel.FoodModel?
				return FoodModel.ForItem(item.Id, item.Kind, world, Vector3.new(3, 3, 3))
			end
		)
	end
end

return FoodPreview
