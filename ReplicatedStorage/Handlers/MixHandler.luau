--!strict
-- Drives the selected mixer's authored world-space ingredient card. Guest orders belong to OrderHandler.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local FoodPreview = require(_Shared.UI.FoodPreview)
local IngredientChip = require(_Shared.UI.IngredientChip)
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local Buildings = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local Ingredients = require(_Configs.Registries.Ingredients)
local GardenSource = require(_Shared.GardenSource)
local InteractHandler = require(_Handlers.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Press = require(_Shared.UI.Press)
local Recipes = require(_Configs.Registries.Recipes)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local BILLBOARD_PATH = "MixerBillboardTemplate"
local REFRESH_INTERVAL = 0.2
local STATION_KIND = "Mixer"
local MIXER_ID = Buildings.GetId("Mixer", 1)

--[[ Tables ]]--
local MixHandler = {
	-- The mixer prop has to be tracked before the Billboard can bind to its authored bowl.
	dependencies = { "DataClient", "InteractHandler", "UIHandler" },
	priority = 80,
}

--[[ Private Functions ]]--
local SetPair = Authored.SetPair

local function GetMixerState(): any?
	local stations = DataClient:GetData({ "Stations" }, "Session") or {}
	for _, station in stations do
		if station.Kind == STATION_KIND then
			return station
		end
	end
	return nil
end

local function IngredientName(ingredientId: string): string
	local ingredient = Ingredients:Get(ingredientId)

	return if ingredient then ingredient.name else ingredientId
end

-- One slot per required unit mirrors the reference: flour x4 becomes four separate flour chips.
local function IngredientUnits(recipe: Recipes.RecipeEntry): { { Id: string, Required: number } }
	local ingredients = {}
	for ingredientId, amount in recipe.ingredients do
		ingredients[#ingredients + 1] = {
			Id = ingredientId,
			Name = IngredientName(ingredientId),
			Amount = amount,
		}
	end
	table.sort(ingredients, function(left, right): boolean
		return left.Name < right.Name
	end)

	local units = {}
	for _, ingredient in ingredients do
		for required = 1, ingredient.Amount do
			units[#units + 1] = { Id = ingredient.Id, Required = required }
		end
	end

	return units
end

local function MaxIngredientUnits(): number
	local most = 0
	for _, recipe in Recipes:Values() do
		local count = 0
		for _, amount in recipe.ingredients do
			count += amount
		end
		most = math.max(most, count)
	end

	return most
end

--[[ Handling ]]--
function MixHandler.OnStart(self: MixHandler): ()
	self.Janitor = Janitor.new()
	self.Accumulator = 0
	self:BuildBillboard()

	DataClient:WaitForData()
	self:Refresh()

	for _, path in { { "Cooking" }, { "Stations" } } do
		self.Janitor:Add(
			DataClient:SubscribeToPath(path, function()
				self:Refresh()
			end, "Session", true),
			"Disconnect"
		)
	end

	self.Janitor:Add(
		RunService.Heartbeat:Connect(function(deltaTime: number)
			self.Accumulator += deltaTime
			if self.Accumulator >= REFRESH_INTERVAL then
				self.Accumulator = 0
				self:RefreshBillboard()
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		UIHandler.Hud.Destroying:Connect(function()
			self:Destroy()
		end),
		"Disconnect"
	)
end

function MixHandler.BuildBillboard(self: MixHandler): ()
	local template = UIHandler:GetHud(BILLBOARD_PATH)
	if not template:IsA("BillboardGui") then
		print("[MixHandler] the authored mixer Billboard is missing")
		return
	end

	local billboard = template:Clone()
	billboard.Name = "MixerBillboard"
	billboard.Enabled = false
	billboard.Parent = UIHandler.Hud.Parent

	local card = billboard:FindFirstChild("Card")
	local holder = card and card:FindFirstChild("Items")
	local done = holder and holder:FindFirstChild("Done")
	local notDone = holder and holder:FindFirstChild("NotDone")
	local chipIcon = done and done:FindFirstChild("Icon")
	if
		not card
		or not card:IsA("Frame")
		or not holder
		or not done
		or not done:IsA("Frame")
		or not notDone
		or not notDone:IsA("Frame")
		or not chipIcon
		or not chipIcon:IsA("ImageLabel")
	then
		billboard:Destroy()
		print("[MixHandler] the authored mixer Billboard has no reusable ingredient chips")
		return
	end

	self.Billboard = billboard
	self.Janitor:Add(billboard, "Destroy")
	self.BillboardCard = card
	self.BillboardChips = {}
	local doneTemplate = done:Clone()
	local notDoneTemplate = notDone:Clone()
	IngredientChip.Prepare(notDoneTemplate, chipIcon)
	IngredientChip.Prepare(doneTemplate, chipIcon)
	for _, chip in holder:GetChildren() do
		if chip:IsA("Frame") then
			chip:Destroy()
		end
	end

	for index = 1, MaxIngredientUnits() do
		local doneClone = doneTemplate:Clone()
		doneClone.Name = `Done{index}`
		doneClone.LayoutOrder = index
		doneClone.Visible = false
		doneClone.Parent = holder
		self.Janitor:Add(Animate.Scale(doneClone), "destroy")

		local notDoneClone = notDoneTemplate:Clone()
		notDoneClone.Name = `NotDone{index}`
		notDoneClone.LayoutOrder = index
		notDoneClone.Visible = false
		notDoneClone.Parent = holder
		self.Janitor:Add(
			Press.Bind(notDoneClone, function()
				local ingredientId = notDoneClone:GetAttribute("IngredientId")
				if
					typeof(ingredientId) == "string"
					and not Ingredients:IsInfinite(ingredientId)
					and (DataClient:GetData({ "Pantry", ingredientId }) or 0) > 0
				then
					Bus.Kitchen.TakePantry:Fire(MIXER_ID, ingredientId)
				end
			end),
			"Destroy"
		)

		self.BillboardChips[index] = { Done = doneClone, NotDone = notDoneClone }
	end
	doneTemplate:Destroy()
	notDoneTemplate:Destroy()
end

function MixHandler.Refresh(self: MixHandler): ()
	self:RefreshBillboard()
end

function MixHandler.RefreshBillboard(self: MixHandler): ()
	local billboard = self.Billboard
	local card = self.BillboardCard
	if not billboard or not card then
		return
	end

	if not billboard.Adornee or not billboard.Adornee.Parent then
		local mixerPart = InteractHandler:GetProp(MIXER_ID)
		local worldModel = mixerPart and (Buildings.WorldModel(mixerPart) or mixerPart)
		if worldModel and worldModel:IsA("BasePart") then
			billboard.Adornee = worldModel
		end
	end

	local selectedId = DataClient:GetData({ "Cooking", "SelectedRecipeId" }, "Session")
	local recipe = selectedId and Recipes:Get(selectedId)
	local adornee: Instance? = billboard.Adornee
	local visible = recipe ~= nil and Recipes:GetStartStation(recipe) == STATION_KIND and adornee ~= nil
	billboard.Enabled = visible
	if not recipe or not visible then
		return
	end

	SetPair(card:FindFirstChild("FoodName"), `Cooking: {recipe.name}`)
	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		FoodPreview.Show(icon, recipe)
	end

	local mixer = GetMixerState()
	local loaded = (mixer and mixer.Loaded) or {}
	local units = IngredientUnits(recipe)
	local hints = {}
	local seen = {}
	local cloud = DataClient:GetData({})
	for index, chip in self.BillboardChips do
		local unit = units[index]
		if not unit then
			chip.Done.Visible = false
			chip.NotDone.Visible = false
			chip.NotDone:SetAttribute("IngredientId", nil)
			continue
		end

		local complete = (loaded[unit.Id] or 0) >= unit.Required
		IngredientChip.Show(chip.Done, unit.Id, IngredientName(unit.Id))
		IngredientChip.Show(chip.NotDone, unit.Id, IngredientName(unit.Id))
		if not complete and not Ingredients:IsInfinite(unit.Id) and not seen[unit.Id] then
			hints[#hints + 1] = `{IngredientName(unit.Id)}: {GardenSource.Describe(unit.Id, cloud)}`
			seen[unit.Id] = true
		end
		if complete and not chip.Done.Visible then
			Animate.Pop(chip.Done)
		end
		chip.Done.Visible = complete
		chip.NotDone.Visible = not complete
	end
	local hint = card:FindFirstChild("SourceHint")
	if hint and hint:IsA("TextLabel") then
		hint.Text = table.concat(hints, "\n")
		hint.Visible = #hints > 0
	end
end

function MixHandler.Destroy(self: MixHandler): ()
	self.Janitor:Destroy()
end

export type MixHandler = typeof(MixHandler) & {
	Janitor: any,
	Billboard: BillboardGui?,
	BillboardCard: Frame?,
	BillboardChips: { [number]: { Done: Frame, NotDone: Frame } },
	Accumulator: number,
}

return MixHandler :: MixHandler
