--!strict
-- Reuses the authored food viewport for ingredient and tool previews as well as dishes.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local CarryModel = require(ReplicatedStorage.Shared.CarryModel)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local FoodModel = require(ReplicatedStorage.Shared.FoodModel)
local FoodPreview = require(script.Parent.Parent.FoodPreview)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(ReplicatedStorage.Shared.Configs.Registries.Recipes)

--[[ Tables ]]--
local Preview = {}
Preview.__index = Preview

--[[ Handling ]]--
function Preview.new(icon: ImageLabel, template: ViewportFrame): Preview
	return setmetatable({ Icon = icon, Template = template, Janitor = Janitor.new(), Key = "" }, Preview)
end

function Preview.Show(self: Preview, goal: any): ()
	local key = (goal.itemKind or "") .. ":" .. (goal.itemId or goal.recipeId or "")
	if self.Key == key then
		return
	end
	self.Key = key
	self.Janitor:Cleanup()
	FoodPreview.Clear(self.Icon)
	self.Icon.Image = ""
	local recipe = goal.recipeId and Recipes:Get(goal.recipeId)
	if not goal.itemId then
		if recipe then
			FoodPreview.Show(self.Icon, recipe)
		end
		return
	end
	if not goal.itemKind or goal.itemKind == "Ingredient" then
		FoodPreview.ShowIngredient(self.Icon, goal.itemId)
		return
	end
	local viewport = self.Template:Clone()
	self.Janitor:Add(viewport, "Destroy")
	local world = viewport:FindFirstChildWhichIsA("WorldModel")
	if not world then
		return
	end
	local visual = nil
	if goal.itemKind == "Tool" then
		local kind = Buildings.KindForTool(goal.itemId)
		local source = kind and kind.HeldAsset and Buildings.FindAsset(kind.HeldAsset)
		if source then
			visual = FoodModel.FromSource(source, world, Vector3.new(2, 3, 2), false)
		end
	else
		visual = CarryModel.new({ Kind = goal.itemKind or "Ingredient", Id = goal.itemId }, world)
	end
	if not visual then
		if recipe then
			FoodPreview.Show(self.Icon, recipe)
		end
		return
	end
	self.Janitor:Add(visual, "Destroy")
	visual:SetCFrame(CFrame.new())
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = viewport
	local center = Vector3.new(0, visual.Size.Y / 2, 0)
	local distance = visual.Size.Magnitude / (2 * math.sin(math.rad(17.5))) * 1.1
	camera.CFrame = CFrame.lookAt(center + Vector3.new(1, 0.8, 1.4).Unit * distance, center)
	viewport.CurrentCamera = camera
	viewport.Visible = true
	viewport.ZIndex = self.Icon.ZIndex
	viewport.Parent = self.Icon
end

function Preview.Destroy(self: Preview): ()
	FoodPreview.Clear(self.Icon)
	self.Janitor:Destroy()
end

export type Preview = typeof(setmetatable(
	{} :: { Icon: ImageLabel, Template: ViewportFrame, Janitor: any, Key: string },
	Preview
))

return Preview
