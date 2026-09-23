--!strict
-- The station pick: which of today's menu recipes the mixer works on next.
--
-- Drives the RecipeToCook screen authored in StarterGui. The day menu is decided once, at the end of a
-- day; this page is opened from the mixer prompt and lists what that menu allows here, one row per
-- dish with what it needs, what it pays and a Start button. The row of the recipe in work shows
-- In-Progress instead, and pressing that cancels the batch: loaded produce goes back to the pantry.
--
-- Beside the list the screen carries a small card for the recipe in work with one chip per
-- ingredient, lit as the mixer fills. Nothing is built here; the authored rows and chips are reused.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local FoodPreview = require(_Shared.UI.FoodPreview)
local IngredientChip = require(_Shared.UI.IngredientChip)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local Buildings = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local DayCycleConfig = require(_Configs.DayCycle)
local Ingredients = require(_Configs.Registries.Ingredients)
local GardenSource = require(_Shared.GardenSource)
local Press = require(_Shared.UI.Press)
local Recipes = require(_Configs.Registries.Recipes)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local SCREEN_NAME = "RecipeToCook"
local ROWS_PATH = { "MainFrame", "Container", "Content" }
local CARD_NAME = "Cooking"
local CHIPS_NAME = "Items"
-- The page is opened from the mixer, so only recipes that start there are offered, and the cancel
-- goes to that station. There is one mixer per bakery.
local STATION_KIND = "Mixer"
local MIXER_ID = Buildings.GetId(STATION_KIND, 1)

--[[ Tables ]]--
local RecipePickHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
local resolve = Authored.Resolve
local SetPair = Authored.SetPair

local function IngredientName(ingredientId: string): string
	local ingredient = Ingredients:Get(ingredientId)

	return if ingredient then ingredient.name else ingredientId
end

-- Ingredients of a recipe in a fixed order: the table is a dictionary, and a row that reshuffles its
-- text on every refresh reads as broken.
local function SortedIngredients(recipe: Recipes.RecipeEntry): { { Id: string, Amount: number } }
	local sorted = {}

	for ingredientId, amount in recipe.ingredients do
		sorted[#sorted + 1] = { Id = ingredientId, Amount = amount }
	end

	table.sort(sorted, function(left, right): boolean
		return IngredientName(left.Id) < IngredientName(right.Id)
	end)

	return sorted
end

-- The most ingredients any recipe asks for: that many chips are kept on the card.
local function MaxIngredientCount(): number
	local most = 0

	for _, recipe in Recipes:Values() do
		local count = 0
		for _ in recipe.ingredients do
			count += 1
		end

		most = math.max(most, count)
	end

	return most
end

local function buildNeeded(row: Frame, template: Frame, janitor: any): { Frame }
	local holder = row:FindFirstChild("Nedded")
	local chips = {}
	if not holder or not holder:IsA("Frame") then
		return chips
	end
	for _, label in holder:GetChildren() do
		if label:IsA("TextLabel") then
			label.Visible = false
		end
	end
	for index = 1, MaxIngredientCount() do
		local chip = template:Clone()
		chip.Name = `Ingredient{index}`
		chip.Visible = false
		-- The authored grid owns square sizing across wide and compact row layouts.
		chip.LayoutOrder = index
		chip.Parent = holder
		janitor:Add(chip, "Destroy")
		chips[index] = chip
	end
	return chips
end

local function MixerState(): any?
	local stations = DataClient:GetData({ "Stations" }, "Session") or {}

	for _, station in stations do
		if station.Kind == STATION_KIND then
			return station
		end
	end

	return nil
end

local function SelectedRecipe(): Recipes.RecipeEntry?
	local recipeId = DataClient:GetData({ "Cooking", "SelectedRecipeId" }, "Session")

	return if typeof(recipeId) == "string" then Recipes:Get(recipeId) else nil
end

-- Today's menu, as the mixer sees it: coffee and anything else that starts elsewhere is left out.
local function MixerMenu(): { Recipes.RecipeEntry }
	local menu = DataClient:GetData({ "Day", "Menu" }, "Session") or {}
	local offered = {}

	for index = 1, #menu do
		local recipe = Recipes:Get(menu[index])
		if recipe and Recipes:GetStartStation(recipe) == STATION_KIND then
			offered[#offered + 1] = recipe
		end
	end

	return offered
end

--[[ Handling ]]--
function RecipePickHandler.OnStart(self: RecipePickHandler): ()
	local screen = UIHandler:GetPanel(SCREEN_NAME)
	local content = screen and resolve(screen, ROWS_PATH)
	if not screen or not content then
		warn(`[RecipePickHandler] '{SCREEN_NAME}' is missing; the station pick is disabled`)
		return
	end

	self.Screen = screen
	self.Janitor = Janitor.new()
	self.Content = content
	self.Rows = {}
	self.Chips = {}
	self.NeededChips = {}

	self:BuildCard()
	self:BuildRows()
	self.Janitor:Add(
		screen.Destroying:Connect(function(): ()
			self:Destroy()
		end),
		"Disconnect"
	)

	DataClient:WaitForData()
	self:Refresh()
	for _, path in { { "Pantry" }, { "Garden" }, { "Base", "Upgrades" } } do
		self.Janitor:Add(
			DataClient:SubscribeToPath(path, function()
				self:RefreshCard()
			end, "Cloud", true),
			"Disconnect"
		)
	end

	for _, path in { { "Day", "Menu" }, { "Cooking" }, { "Stations" } } do
		self.Janitor:Add(
			DataClient:SubscribeToPath(path, function()
				self:Refresh()
			end, "Session", true),
			"Disconnect"
		)
	end
end

--- Collects the authored rows and adds copies until the whole menu fits. Rows are then ordered by
--- code, not by name: they are renamed after the dish they hold so the tutorial can point at one.
function RecipePickHandler.BuildRows(self: RecipePickHandler): ()
	local rows = {}

	for _, row in self.Content:GetChildren() do
		if row:IsA("Frame") then
			rows[#rows + 1] = row
		end
	end

	if #rows == 0 then
		warn("[RecipePickHandler] the recipe list has no rows to fill")
		return
	end

	table.sort(rows, function(left: Frame, right: Frame): boolean
		return left.Name < right.Name
	end)

	local layout = self.Content:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	local template = rows[1]:Clone()
	for index = #rows + 1, DayCycleConfig.MenuMax do
		local clone = template:Clone()
		clone.Parent = self.Content
		self.Janitor:Add(clone, "Destroy")
		rows[index] = clone
	end
	template:Destroy()

	for index, row in rows do
		row.LayoutOrder = index
		row.Visible = false
		self.Rows[index] = row
		local foodIcon = resolve(row, { "IconAndName", "Icon" })
		if foodIcon and foodIcon:IsA("ImageLabel") then
			self.Janitor:Add(function(): ()
				FoodPreview.Clear(foodIcon)
			end)
		end
		if self.NeededTemplate then
			self.NeededChips[row] = buildNeeded(row, self.NeededTemplate, self.Janitor)
		end

		local start = resolve(row, { "Status", "Start" })
		if start and start:IsA("GuiObject") then
			Animate.Press(start)
			self.Janitor:Add(
				Press.BindTap(start, function()
					local recipeId = row:GetAttribute("RecipeId")
					if typeof(recipeId) == "string" then
						Bus.Kitchen.SelectRecipe:Fire(recipeId)
					end
				end),
				"Destroy"
			)
		end

		local inProgress = resolve(row, { "Status", "InProgress" })
		if inProgress and inProgress:IsA("GuiObject") then
			Animate.Press(inProgress)
			self.Janitor:Add(
				Press.BindTap(inProgress, function()
					Bus.Kitchen.Cancel:Fire(MIXER_ID)
				end),
				"Destroy"
			)
		end
	end
end

--- The card's chips are drawn twice over, one lit and one not. Both are kept per place and toggled,
--- the way the day menu keeps its picked plates.
function RecipePickHandler.BuildCard(self: RecipePickHandler): ()
	local card = resolve(self.Screen, { "MainFrame", CARD_NAME })
	local content = card and card:FindFirstChild("Content")
	local holder = content and content:FindFirstChild(CHIPS_NAME)
	if not card or not card:IsA("ScrollingFrame") or not content or not content:IsA("Frame") or not holder then
		warn("[RecipePickHandler] the cooking card is missing; only the list is shown")
		return
	end

	local done = holder:FindFirstChild("Done")
	local notDone = holder:FindFirstChild("NotDone")
	local chipIcon = done and done:FindFirstChild("Icon")
	if
		not done
		or not done:IsA("Frame")
		or not notDone
		or not notDone:IsA("Frame")
		or not chipIcon
		or not chipIcon:IsA("ImageLabel")
	then
		warn("[RecipePickHandler] the cooking card has no chips to reuse")
		return
	end

	self.Card = card
	self.CardContent = content
	local foodIcon = resolve(content, { "Header", "Icon" })
	if foodIcon and foodIcon:IsA("ImageLabel") then
		self.Janitor:Add(function(): ()
			FoodPreview.Clear(foodIcon)
		end)
	end

	-- Detached copies first: the drawn chips themselves are cleared away right after.
	local doneTemplate = done:Clone()
	local notDoneTemplate = notDone:Clone()
	IngredientChip.Prepare(notDoneTemplate, chipIcon)
	IngredientChip.Prepare(doneTemplate, chipIcon)
	self.NeededTemplate = notDoneTemplate
	self.Janitor:Add(notDoneTemplate, "Destroy")

	for _, chip in holder:GetChildren() do
		if chip:IsA("Frame") then
			chip:Destroy()
		end
	end

	for index = 1, MaxIngredientCount() do
		local doneClone = doneTemplate:Clone()
		doneClone.Name = `Done{index}`
		doneClone.LayoutOrder = index
		doneClone.Visible = false
		doneClone.Parent = holder
		self.Janitor:Add(doneClone, "Destroy")
		self.Janitor:Add(Animate.Scale(doneClone), "destroy")

		local notDoneClone = notDoneTemplate:Clone()
		notDoneClone.Name = `NotDone{index}`
		notDoneClone.LayoutOrder = index
		notDoneClone.Visible = false
		notDoneClone.Parent = holder
		self.Janitor:Add(notDoneClone, "Destroy")
		self.Janitor:Add(
			Press.BindTap(notDoneClone, function(): ()
				local id = notDoneClone:GetAttribute("IngredientId")
				if typeof(id) ~= "string" or Ingredients:IsInfinite(id) then
					return
				end
				if (DataClient:GetData({ "Pantry", id }) or 0) <= 0 then
					return
				end
				Bus.Kitchen.TakePantry:Fire(MIXER_ID, id)
			end),
			"Destroy"
		)

		self.Chips[index] = { Done = doneClone :: Frame, NotDone = notDoneClone :: Frame }
	end
	doneTemplate:Destroy()
end

function RecipePickHandler.Refresh(self: RecipePickHandler): ()
	self:RefreshRows()
	self:RefreshCard()
end

function RecipePickHandler.RefreshRows(self: RecipePickHandler): ()
	local selected = SelectedRecipe()
	local menu = MixerMenu()

	for index, row in self.Rows do
		local recipe = menu[index]
		if not recipe then
			row:SetAttribute("RecipeId", nil)
			row.Name = `Row{index}`
			row.Visible = false
			continue
		end

		self:PaintRow(row, recipe, selected ~= nil and selected.id == recipe.id)
	end
end

function RecipePickHandler.PaintRow(
	self: RecipePickHandler,
	row: Frame,
	recipe: Recipes.RecipeEntry,
	inWork: boolean
): ()
	row:SetAttribute("RecipeId", recipe.id)
	-- Named after what it holds so the tutorial can point at one dish by path.
	row.Name = recipe.id
	row.Visible = true
	local background = row:FindFirstChild("Bg")
	if background and background:IsA("GuiObject") then
		if background:GetAttribute("UnselectedColor") == nil then
			background:SetAttribute("UnselectedColor", background.BackgroundColor3)
		end
		background.BackgroundColor3 = if inWork
			then Color3.fromRGB(196, 242, 170)
			else background:GetAttribute("UnselectedColor") :: Color3
		local stroke = background:FindFirstChildOfClass("UIStroke")
		if stroke then
			if stroke:GetAttribute("UnselectedColor") == nil then
				stroke:SetAttribute("UnselectedColor", stroke.Color)
				stroke:SetAttribute("UnselectedThickness", stroke.Thickness)
			end
			stroke.Color = if inWork
				then Color3.fromRGB(34, 169, 0)
				else stroke:GetAttribute("UnselectedColor") :: Color3
			local authoredThickness = stroke:GetAttribute("UnselectedThickness") :: number
			local selectedThickness = if stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize
				then authoredThickness * 2
				else 4
			stroke.Thickness = if inWork then selectedThickness else authoredThickness
		end
	end

	SetPair(resolve(row, { "IconAndName", "Name" }), recipe.name)
	local needed = SortedIngredients(recipe)
	for index, chip in (self.NeededChips[row] or {}) :: { Frame } do
		local entry = needed[index]
		chip.Visible = entry ~= nil
		if not entry then
			continue
		end
		local name = IngredientName(entry.Id)
		IngredientChip.Show(chip, entry.Id, if entry.Amount > 1 then `{name} x{entry.Amount}` else name)
	end
	SetPair(resolve(row, { "Reward", "Txt" }), `Reward: {UIHandler:FormatNumber(recipe.price)}`)

	local icon = resolve(row, { "IconAndName", "Icon" })
	if icon and icon:IsA("ImageLabel") then
		FoodPreview.Show(icon, recipe)
	end

	local start = resolve(row, { "Status", "Start" })
	if start and start:IsA("GuiObject") then
		start.Visible = not inWork
	end

	local inProgress = resolve(row, { "Status", "InProgress" })
	if inProgress and inProgress:IsA("GuiObject") then
		-- A punch the moment the dish goes into work, so the switch is felt and not only seen.
		if inWork and not inProgress.Visible then
			Animate.Pop(inProgress)
		end

		inProgress.Visible = inWork
	end
end

--- The card follows the recipe in work: its name and icon, and one chip per ingredient that lights
--- up once the mixer holds enough of it.
function RecipePickHandler.RefreshCard(self: RecipePickHandler): ()
	local card = self.Card
	local content = self.CardContent
	if not card or not content then
		return
	end

	local recipe = SelectedRecipe()
	card.Visible = true
	local empty = content:FindFirstChild("EmptyState")
	if empty and empty:IsA("GuiObject") then
		empty.Visible = recipe == nil
	end
	for _, name in { "Header", "Items", "SourceHint" } do
		local element = content:FindFirstChild(name)
		if element and element:IsA("GuiObject") then
			element.Visible = recipe ~= nil
		end
	end
	if not recipe then
		return
	end

	SetPair(resolve(content, { "Header", "FoodName" }), recipe.name)

	local icon = resolve(content, { "Header", "Icon" })
	if icon and icon:IsA("ImageLabel") then
		FoodPreview.Show(icon, recipe)
	end

	local mixer = MixerState()
	local loaded = (mixer and mixer.Loaded) or {}
	local needed = SortedIngredients(recipe)
	local hints = {}
	local cloud = DataClient:GetData({})

	for index, chip in self.Chips do
		local entry = needed[index]
		if not entry then
			chip.Done.Visible = false
			chip.NotDone.Visible = false
			continue
		end

		local have = loaded[entry.Id] or 0
		chip.NotDone:SetAttribute("IngredientId", entry.Id)
		local complete = have >= entry.Amount
		if not complete and not Ingredients:IsInfinite(entry.Id) then
			hints[#hints + 1] = `{IngredientName(entry.Id)}: {GardenSource.Describe(entry.Id, cloud)}`
		end
		local text = `{IngredientName(entry.Id)} {math.min(have, entry.Amount)}/{entry.Amount}`

		IngredientChip.Show(chip.Done, entry.Id, text)
		IngredientChip.Show(chip.NotDone, entry.Id, text)

		-- Lit chips spring in only as they light up, not on every refresh.
		if complete and not chip.Done.Visible then
			Animate.Pop(chip.Done)
		end

		chip.Done.Visible = complete
		chip.NotDone.Visible = not complete
	end
	local hint = content:FindFirstChild("SourceHint")
	if hint and hint:IsA("TextLabel") then
		hint.Text = table.concat(hints, "\n")
		hint.Visible = #hints > 0
	end
end

function RecipePickHandler.Destroy(self: RecipePickHandler): ()
	self.Janitor:Destroy()
end

export type ChipPair = { Done: Frame, NotDone: Frame }

export type RecipePickHandler = typeof(RecipePickHandler) & {
	Screen: ScreenGui,
	Content: Instance,
	Rows: { Frame },
	Card: ScrollingFrame?,
	CardContent: Frame?,
	Chips: { ChipPair },
	Janitor: any,
	NeededTemplate: Frame?,
	NeededChips: { [Frame]: { Frame } },
}

return RecipePickHandler :: RecipePickHandler
