--!strict
-- Clones the authored viewport into an item icon. UIHandler supplies the screen template.

--[[ Services ]]
--
local ContentProvider = game:GetService("ContentProvider")
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

--[[ Constants ]]
--
-- The three-quarter angle every preview is seen from.
local VIEW_DIRECTION = Vector3.new(1, 0.9, 1.5).Unit
-- Breathing room around the silhouette, as a share of its half-extent.
local FRAME_MARGIN = 1.08
-- Rays per side of the grid that traces the silhouette.
local SAMPLES = 20
-- Long, thin items (a broom) lie along the tile's diagonal; everything else stays upright.
local DIAGONAL_ROLL = math.rad(40)
-- Outline length to width from which an item counts as long and thin.
local ELONGATED = 2.5
-- Camera step that forces a redraw without a visible change.
local REDRAW_NUDGE = CFrame.new(0, 0, 1e-3)

--[[ Tables ]]
--
local FoodPreview = {}
local template: ViewportFrame? = nil
local previews: { [ImageLabel]: { Key: string, Janitor: any } } = {}

--[[ Private Functions ]]
--
-- Points on the visible surface, traced by a grid of rays along the view. A bounding box framed
-- round food (an egg, a pie) with half the tile empty; the traced outline is what actually shows.
-- Falls back to the box corners when nothing is hit.
local function silhouette(world: WorldModel): ({ Vector3 }, number)
	local boxFrame, boxSize = world:GetBoundingBox()
	local center, half = boxFrame.Position, boxSize / 2
	local view = CFrame.lookAt(Vector3.zero, -VIEW_DIRECTION)
	local right, up = view.RightVector, view.UpVector
	local function reach(axis: Vector3): number
		return math.abs(half.X * axis.X) + math.abs(half.Y * axis.Y) + math.abs(half.Z * axis.Z)
	end
	local width, height, depth = reach(right), reach(up), reach(VIEW_DIRECTION) + 1
	local cell = math.max(width, height) * 2 / SAMPLES

	local parts: { BasePart } = {}
	for _, part in world:GetDescendants() do
		if part:IsA("BasePart") then
			-- Preview copies only: invisible helpers (grips, hitboxes) must not stretch the outline.
			part.CanQuery = part.Transparency < 1
			if part.CanQuery then
				parts[#parts + 1] = part
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Only the visible parts were made queryable above.
	params.FilterDescendantsInstances = { world }
	local points: { Vector3 } = {}
	for column = 0, SAMPLES do
		for row = 0, SAMPLES do
			local offset = right * width * (column / SAMPLES * 2 - 1) + up * height * (row / SAMPLES * 2 - 1)
			local hit = world:Raycast(center + offset + VIEW_DIRECTION * depth, -VIEW_DIRECTION * depth * 2, params)
			if hit then
				points[#points + 1] = hit.Position
			end
		end
	end
	for _, part in parts do
		part.CanQuery = false
	end

	if #points == 0 then
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					points[#points + 1] = center + half * Vector3.new(x, y, z)
				end
			end
		end
		cell = 0
	end
	return points, cell
end

-- Aim point and camera distance that fit `points` into a square view rolled by `roll`, and the
-- outline's length-to-width ratio in that view.
local function fit(points: { Vector3 }, pad: number, fieldOfView: number, roll: number): (Vector3, number, number)
	local view = CFrame.lookAt(Vector3.zero, -VIEW_DIRECTION) * CFrame.Angles(0, 0, roll)
	local right, up = view.RightVector, view.UpVector
	local minX, maxX, minY, maxY, depth = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, point in points do
		local x, y = point:Dot(right), point:Dot(up)
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
		depth += point:Dot(VIEW_DIRECTION)
	end
	local aim = right * (minX + maxX) / 2 + up * (minY + maxY) / 2 + VIEW_DIRECTION * depth / #points
	local tanHalf = math.tan(math.rad(fieldOfView / 2))
	local distance = 0
	for _, point in points do
		local offset = point - aim
		local lateral = math.max(math.abs(offset:Dot(right)), math.abs(offset:Dot(up))) + pad / 2
		distance = math.max(distance, offset:Dot(VIEW_DIRECTION) + lateral * FRAME_MARGIN / tanHalf)
	end
	local long = math.max(maxX - minX, maxY - minY)
	local short = math.max(math.min(maxX - minX, maxY - minY), 0.001)
	return aim, distance, long / short
end

local function frame(camera: Camera, world: WorldModel): ()
	local points, pad = silhouette(world)
	local roll = 0
	local aim, distance, aspect = fit(points, pad, camera.FieldOfView, 0)
	local rolledAim, rolled = fit(points, pad, camera.FieldOfView, -DIAGONAL_ROLL)
	if aspect >= ELONGATED and rolled < distance then
		roll, aim, distance = -DIAGONAL_ROLL, rolledAim, rolled
	end
	camera.CFrame = CFrame.lookAt(aim + VIEW_DIRECTION * distance, aim) * CFrame.Angles(0, 0, roll)
end

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
	viewport.CurrentCamera = camera
	viewport.Name = "FoodPreview"
	viewport.ZIndex = icon.ZIndex
	viewport.Visible = true
	icon.ImageTransparency = 1
	viewport.Parent = icon
	-- A WorldModel only answers raycasts once it is inside the DataModel.
	frame(camera, world)

	-- A ViewportFrame redraws only when its contents, camera or properties change. In Studio the
	-- meshes and textures come from the local cache and are ready for the first draw; a live client
	-- downloads them afterwards, and a still preview (a guest's order bubble) stayed empty. Once the
	-- assets have arrived, frame again (mesh collision now answers the silhouette rays) and nudge
	-- the camera so the viewport draws the loaded model.
	local preview = previews[icon]
	janitor:Add(
		task.spawn(function(): ()
			pcall(ContentProvider.PreloadAsync, ContentProvider, world:GetDescendants())
			if previews[icon] ~= preview or not viewport.Parent then
				return
			end
			frame(camera, world)
			camera.CFrame *= REDRAW_NUDGE
		end),
		true
	)
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
		return FoodModel.ForItem(recipe.id, foodKind, world, Config.PreviewSize)
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
		return if source then FoodModel.FromSource(source, world, Config.PreviewSize) else nil
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
				return FoodModel.ForItem(item.Id, item.Kind, world, Config.PreviewSize)
			end
		)
	end
end

return FoodPreview
