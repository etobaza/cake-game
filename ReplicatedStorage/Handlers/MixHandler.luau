--!strict
-- Drives the selected mixer's authored world-space ingredient card. Guest orders belong to OrderHandler.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local FoodPreview = require(_Shared.UI.FoodPreview)
local IngredientCard = require(_Shared.UI.IngredientCard)
local InputCue = require(_Shared.UI.InputCue)
local InputCues = require(_Configs.InputCues)
local Authored = require(_Shared.UI.Authored)
local Buildings = require(_Configs.Buildings)
local DataClient = require(_Handlers.DataHandlerClient)
local Ingredients = require(_Configs.Registries.Ingredients)
local InteractHandler = require(_Handlers.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local MixerInteraction = require(_Configs.MixerInteraction)
local Pages = require(_Shared.UI.Stores.Pages)
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

local function PantryCount(ingredientId: string): number
	return DataClient:GetData({ "Pantry", ingredientId }) or 0
end

-- The floating card shows from across the kitchen; the gamepad shortcut works only at the mixer.
local function InMixerReach(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local mixer = InteractHandler:GetProp(MIXER_ID)
	return root ~= nil
		and root:IsA("BasePart")
		and mixer ~= nil
		and (root.Position - mixer.Position).Magnitude <= InputCues.MixerReach
end

--[[ Handling ]]--
function MixHandler.OnStart(self: MixHandler): ()
	self.Janitor = Janitor.new()
	self.Accumulator = 0
	self:BuildBillboard()
	self:FitBillboard()
	self.Janitor:Add(
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function(): ()
			self:FitBillboard()
		end),
		"Disconnect"
	)

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
	local doneTemplate: Frame?, notDoneTemplate: Frame? = nil, nil
	if holder then
		doneTemplate, notDoneTemplate = IngredientCard.Templates(holder)
	end
	if not card or not card:IsA("Frame") or not holder or not doneTemplate or not notDoneTemplate then
		if doneTemplate then
			doneTemplate:Destroy()
		end
		if notDoneTemplate then
			notDoneTemplate:Destroy()
		end
		billboard:Destroy()
		print("[MixHandler] the authored mixer Billboard has no reusable ingredient chips")
		return
	end

	self.Billboard = billboard
	self.Janitor:Add(billboard, "Destroy")
	self.AuthoredSize = billboard.Size
	self.AuthoredOffset = billboard.StudsOffsetWorldSpace
	self.BillboardCard = card
	-- One chip per required unit mirrors the reference: flour x4 becomes four separate flour chips.
	-- The billboard floats in the world, so its chips press on contact and leave the camera alone.
	local chipOptions: IngredientCard.ChipOptions = { StationId = MIXER_ID, PantryCount = PantryCount, Floating = true }
	self.BillboardChips = IngredientCard.BuildChips(
		holder,
		doneTemplate,
		notDoneTemplate,
		IngredientCard.MostUnits(),
		self.Janitor,
		chipOptions
	)
	doneTemplate:Destroy()
	notDoneTemplate:Destroy()

	-- A gamepad cannot point at the floating chips: its shoulder button loads the next pantry chip,
	-- and the glyph shows on the card only while there is one and no page covers the world.
	local function nextChip(): Frame?
		if Pages.Current:peek() ~= Pages.Names.None then
			return nil
		end
		return IngredientCard.NextPantryChip(self.BillboardChips, chipOptions)
	end
	self.PantryCue = InputCue.Bind({
		Name = "MixerPantry",
		Target = card,
		Key = InputCues.Keys.MixerPantry,
		Action = function(): ()
			local chip = nextChip()
			if chip then
				IngredientCard.TakeFromPantry(chip, chipOptions)
			end
		end,
		Available = function(): boolean
			return billboard.Enabled and InMixerReach() and nextChip() ~= nil
		end,
		Shown = function(): boolean
			return nextChip() ~= nil
		end,
	})
	self.Janitor:Add(self.PantryCue, "Destroy")

	-- The mixer prompt offers Recipes only while no dish is chosen, so the card's dish name and
	-- picture open the list to change it. Like the chips, they press on contact.
	local function openRecipes(): ()
		Pages.Open(Pages.Names.RecipeToCook)
	end
	for _, name in { "FoodName", "Icon" } do
		local header = card:FindFirstChild(name)
		if header and header:IsA("GuiObject") then
			self.Janitor:Add(Press.Bind(header, openRecipes), "Destroy")
			self.Janitor:Add(Press.SinkUnlessMouse(header), "Destroy")
		end
	end
	local foodName = card:FindFirstChild("FoodName")
	if foodName and foodName:IsA("GuiObject") then
		self.RecipesCue = InputCue.Bind({
			Name = "MixerRecipes",
			Target = foodName,
			Key = InputCues.Keys.MixerRecipes,
			Placement = "Left",
			Action = openRecipes,
			Available = function(): boolean
				return billboard.Enabled and InMixerReach() and Pages.Current:peek() == Pages.Names.None
			end,
			Shown = function(): boolean
				return Pages.Current:peek() == Pages.Names.None
			end,
		})
		self.Janitor:Add(self.RecipesCue, "Destroy")
	end
end

-- The card is sized in studs; a short screen grows it to the pixel size it has on a
-- `CardMinViewportHeight` screen. Its bottom edge stays put, so it grows upward, away from the bowl.
function MixHandler.FitBillboard(self: MixHandler): ()
	local billboard, size, offset = self.Billboard, self.AuthoredSize, self.AuthoredOffset
	if not billboard or not size or not offset then
		return
	end

	local grow = math.max(1, MixerInteraction.CardMinViewportHeight / workspace.CurrentCamera.ViewportSize.Y)
	billboard.Size = UDim2.new(size.X.Scale * grow, size.X.Offset, size.Y.Scale * grow, size.Y.Offset)
	billboard.StudsOffsetWorldSpace = offset + Vector3.new(0, size.Y.Scale * (grow - 1) / 2, 0)
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
		and not Pages.Presenting:peek()
	billboard.Enabled = visible
	if not recipe or not visible then
		return
	end

	SetPair(card:FindFirstChild("FoodName"), `Cooking: {recipe.name}`)
	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		FoodPreview.Show(icon, recipe)
	end

	local loaded = IngredientCard.Loaded(DataClient:GetData({ "Stations" }, "Session"), STATION_KIND)
	local units = IngredientCard.Units(recipe)
	local hints = {}
	local seen = {}
	local cloud = DataClient:GetData({})
	for index, chip in self.BillboardChips do
		local unit = units[index]
		if not unit then
			IngredientCard.HideChip(chip)
			continue
		end

		local complete = (loaded[unit.Id] or 0) >= unit.Required
		IngredientCard.ShowChip(chip, unit.Id, IngredientCard.Name(unit.Id), complete)
		if not complete and not Ingredients:IsInfinite(unit.Id) and not seen[unit.Id] then
			hints[#hints + 1] = IngredientCard.SourceHint(unit.Id, cloud)
			seen[unit.Id] = true
		end
	end
	IngredientCard.ShowHints(card:FindFirstChild("SourceHint"), hints)
	if self.PantryCue then
		self.PantryCue:Refresh()
	end
	if self.RecipesCue then
		self.RecipesCue:Refresh()
	end
end

function MixHandler.Destroy(self: MixHandler): ()
	local janitor = self.Janitor
	if janitor == nil then
		return
	end
	-- Janitor removes its metatable on destruction; release the owner before repeated cleanup.
	self.Janitor = nil
	janitor:Destroy()
end

export type MixHandler = typeof(MixHandler) & {
	Janitor: any,
	Billboard: BillboardGui?,
	-- The template's stud size and offset, before FitBillboard grows them for short screens.
	AuthoredSize: UDim2?,
	AuthoredOffset: Vector3?,
	BillboardCard: Frame?,
	BillboardChips: { IngredientCard.ChipPair },
	-- The gamepad shortcut onto the next pantry chip.
	PantryCue: InputCue.Cue?,
	-- The gamepad shortcut that opens the recipe list from the card.
	RecipesCue: InputCue.Cue?,
	Accumulator: number,
}

return MixHandler :: MixHandler
