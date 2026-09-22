--!strict
-- End-of-day menu: pick 3-5 unlocked recipes for tomorrow, then advance to its prep.
--
-- Drives the Inventory screen authored in StarterGui. That screen was drawn for exactly this: a grid
-- of dishes with a price and a lock, a filter strip, a row of picked recipes with a capacity count,
-- the menu bonuses, and a Next Day button. Nothing is built here; the authored cells are filled in.
--
-- The authored card template is cloned once per recipe. CardGrid adapts the visible cards
-- to the available width. Filtering re-fills the cells from the top and hides
-- spare cells so the scroll canvas follows only the current results.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local CardGrid = require(_Shared.UI.CardGrid)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local FoodPreview = require(_Shared.UI.FoodPreview)
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local DayCycleConfig = require(_Configs.DayCycle)
local Pages = require(_Shared.UI.Stores.Pages)
local Press = require(_Shared.UI.Press)
local Recipes = require(_Configs.Registries.Recipes)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local SCREEN_NAME = "Inventory"
local GRID_PATH = { "MainFrame", "Container", "Content" }
local FILTERS_PATH = { "MainFrame", "Filters" }
local PICKED_PATH = { "MainFrame", "SelectedRecipes", "Content" }
local CAPACITY_PATH = { "MainFrame", "SelectedRecipes", "Top", "Capacity" }
local HEADER_PATH = { "MainFrame", "Header", "Buttons", "NextDay" }
local BONUSES_PATH = { "MainFrame", "Bonuses" }

-- Filter tab name in the drawing, and the station whose dishes it keeps. All keeps everything.
local FILTERS: { { Name: string, Station: string? } } = {
	{ Name = "All", Station = nil },
	{ Name = "2", Station = "Oven" },
	{ Name = "Mixed", Station = "Mixer" },
	{ Name = "Frozen", Station = "Freezer" },
}

local CELL_STROKE_IDLE = Color3.fromRGB(238, 165, 75)
local CELL_STROKE_PICKED = Color3.fromRGB(34, 169, 0)
local FILTER_ON = Color3.fromRGB(247, 233, 205)
local FILTER_OFF = Color3.fromRGB(205, 191, 161)

--[[ Tables ]]--
local MenuHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
local resolve = Authored.Resolve
local SetPair = Authored.SetPair

-- Whether the player owns such a station. Counted from replicated stations, not from upgrades:
-- the server builds Stations from the same stats, so it is the same answer without the extra math.
local function HasStation(stationKind: string): boolean
	local stateField = BuildingsConfig.Kinds[stationKind].StateField :: string
	local stations = DataClient:GetData({ stateField }, "Session") or {}

	for stationId in stations do
		if stations[stationId].Kind == stationKind then
			return true
		end
	end

	return false
end

-- Recipes in unlock order: otherwise the grid jumps around with the registry hash order.
local function GetSortedRecipes(): { Recipes.RecipeEntry }
	local sorted = Recipes:Values()

	table.sort(sorted, function(left: Recipes.RecipeEntry, right: Recipes.RecipeEntry)
		if left.unlockLevel == right.unlockLevel then
			return left.order < right.order
		end

		return left.unlockLevel < right.unlockLevel
	end)

	return sorted
end

--[[ Handling ]]--
function MenuHandler.OnStart(self: MenuHandler): ()
	local screen = UIHandler:GetPanel(SCREEN_NAME)
	local grid = screen and resolve(screen, GRID_PATH)
	local picked = screen and resolve(screen, PICKED_PATH)
	if not screen or not grid or not picked then
		warn(`[MenuHandler] '{SCREEN_NAME}' is missing; the day menu is disabled`)
		return
	end

	self.Janitor = Janitor.new()
	self.Janitor:LinkToInstance(screen)
	self.Screen = screen
	self.Grid = grid
	self.PickedStrip = picked
	self.Cells = {}
	self.PickedSlots = {}
	self.Filters = {}
	self.Selected = {}
	self.Filter = nil

	self:BuildCells()
	self:BuildPickedSlots()
	self:BindFilters()
	self:BindHeader()
	self:CollectBonuses()

	DataClient:WaitForData()
	self:RefreshPhase(DataClient:GetData({ "Day", "Phase" }, "Session"))

	DataClient:SubscribeToPath({ "Level" }, function()
		self:Rebuild()
	end, "Cloud")

	-- A freezer or coffee machine was bought: its recipes become pickable right away.
	DataClient:SubscribeToPath({ "Stations" }, function()
		self:Rebuild()
	end, "Session", true)

	DataClient:SubscribeToPath({ "Day", "NextMenu" }, function()
		if DataClient:GetData({ "Day", "Phase" }, "Session") == "Summary" then
			self:SyncSelection()
			self:Rebuild()
		end
	end, "Session")
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Day", "Menu" }, function()
			if DataClient:GetData({ "Day", "Phase" }, "Session") ~= "Summary" then
				self:SyncSelection()
				self:Rebuild()
			end
		end, "Session"),
		"Disconnect"
	)

	-- Closing is a modal planning step. It stays open until the server accepts Next Day.
	DataClient:SubscribeToPath({ "Day", "Phase" }, function(phase: string)
		self:RefreshPhase(phase)
	end, "Session")
end

function MenuHandler.SyncSelection(self: MenuHandler): ()
	self.Selected = {}

	local field = if DataClient:GetData({ "Day", "Phase" }, "Session") == "Summary" then "NextMenu" else "Menu"
	for _, recipeId in DataClient:GetData({ "Day", field }, "Session") or {} do
		self.Selected[recipeId] = true
	end
end

function MenuHandler.RefreshPhase(self: MenuHandler, _phase: string?): ()
	self:SyncSelection()
	self:Rebuild()
end

--- Clones the authored card once per recipe; filtering only repaints and hides cards.
function MenuHandler.BuildCells(self: MenuHandler): ()
	local template = self.Grid:FindFirstChildWhichIsA("Frame")
	if not template then
		warn("[MenuHandler] recipe card template is missing")
		return
	end
	local count = #Recipes:Values()
	for index = 1, count do
		local cell = if index == 1 then template else template:Clone()
		cell.Name = `Cell{index}`
		cell.LayoutOrder = index
		cell.Visible = false
		cell.Parent = self.Grid
		self.Cells[index] = cell
		Animate.Press(cell)
		self.Janitor:Add(
			Press.BindTap(cell, function()
				local recipeId = cell:GetAttribute("RecipeId")
				if typeof(recipeId) == "string" then
					self:ToggleRecipe(recipeId)
				end
			end),
			"Destroy"
		)
	end
	self.Janitor:Add(CardGrid.Bind(self.Grid :: GuiObject), "Destroy")
end

--- The picked strip is drawn twice over: a filled plate and an empty one for each place. Both are
--- kept and toggled, so a pick never rebuilds instances.
function MenuHandler.BuildPickedSlots(self: MenuHandler): ()
	local filled: Frame?
	local empty: Frame?

	for _, slot in self.PickedStrip:GetChildren() do
		if not slot:IsA("Frame") then
			continue
		end

		if not filled and slot:FindFirstChild("Icon") then
			filled = slot
		elseif not empty and slot:FindFirstChild("Status") then
			empty = slot
		end
	end

	if not filled or not empty then
		warn("[MenuHandler] the picked strip has no plates to reuse")
		return
	end

	-- Detached copies first: the drawn plates themselves are cleared away right after.
	local filledTemplate = filled:Clone()
	local emptyTemplate = empty:Clone()

	for _, slot in self.PickedStrip:GetChildren() do
		if slot:IsA("Frame") then
			slot:Destroy()
		end
	end

	for index = 1, DayCycleConfig.MenuMax do
		local filledClone = filledTemplate:Clone()
		filledClone.Name = `Picked{index}`
		filledClone.LayoutOrder = index
		filledClone.Visible = false
		filledClone.Parent = self.PickedStrip

		local emptyClone = emptyTemplate:Clone()
		emptyClone.Name = `Free{index}`
		emptyClone.LayoutOrder = index
		emptyClone.Visible = true
		emptyClone.Parent = self.PickedStrip

		self.PickedSlots[index] = { Filled = filledClone, Empty = emptyClone }
	end
end

function MenuHandler.BindFilters(self: MenuHandler): ()
	local strip = resolve(self.Screen, FILTERS_PATH)
	if not strip then
		warn("[MenuHandler] the filter strip is missing")
		return
	end

	for _, filter in FILTERS do
		local tab = strip:FindFirstChild(filter.Name)
		if not tab or not tab:IsA("GuiObject") then
			warn(`[MenuHandler] no filter tab named '{filter.Name}'`)
			continue
		end

		self.Filters[filter.Name] = tab

		Animate.Press(tab)
		Press.Bind(tab, function()
			self.Filter = filter.Station
			if self.Grid:IsA("ScrollingFrame") then
				self.Grid.CanvasPosition = Vector2.zero
			end
			self:Rebuild()
		end)
	end
end

function MenuHandler.BindHeader(self: MenuHandler): ()
	local nextDay = resolve(UIHandler.BakeryMenu, HEADER_PATH)
	if not nextDay or not nextDay:IsA("GuiButton") then
		warn("[MenuHandler] BakeryMenu's Next Day button is missing")
		return
	end
	self.Janitor:Add(
		nextDay.Activated:Connect(function(): ()
			self:NextDay()
		end),
		"Disconnect"
	)
end

--- The two bonus lines are each drawn twice, once earned and once not. Which is which is read off
--- the text, because every one of them is named Bonus.
function MenuHandler.CollectBonuses(self: MenuHandler): ()
	local holder = resolve(self.Screen, BONUSES_PATH)
	if not holder then
		return
	end

	local lines: { [string]: BonusPair } = { Vegan = {}, GlutenFree = {} }
	self.Bonuses = lines

	for _, line in holder:GetChildren() do
		if not line:IsA("GuiObject") then
			continue
		end

		local label = line:FindFirstChildWhichIsA("TextLabel")
		local text = if label then string.lower(label.Text) else ""
		local key = if string.find(text, "gluten")
			then "GlutenFree"
			elseif string.find(text, "vegan") then "Vegan"
			else nil
		if not key then
			continue
		end

		local pair = lines[key]
		if string.sub(text, 1, 2) == "no" then
			pair.Off = line
		else
			pair.On = line
		end
	end
end

--- Fills the grid from the current filter, then refreshes everything that reads the picks.
function MenuHandler.Rebuild(self: MenuHandler): ()
	local level = DataClient:GetData({ "Level" }) or 1
	local slot = 0
	local dropped = false

	for _, recipe in GetSortedRecipes() do
		if self.Filter and recipe.station ~= self.Filter then
			continue
		end

		slot += 1
		local cell = self.Cells[slot]
		if not cell then
			warn(`[MenuHandler] the grid ran out of cells at '{recipe.id}'`)
			break
		end

		local selectable = recipe.unlockLevel <= level and HasStation(recipe.station)
		-- The server refuses a recipe without its station, so it cannot stay picked either.
		if not selectable and self.Selected[recipe.id] then
			self.Selected[recipe.id] = nil
			dropped = true
		end

		self:PaintCell(cell, recipe, selectable)
	end

	for index = slot + 1, #self.Cells do
		local cell = self.Cells[index]
		cell:SetAttribute("RecipeId", nil)
		cell.Name = `Cell{index}`
		cell.Visible = false
	end

	self:RefreshFilters()
	self:RefreshPicked()
	self:RefreshBonuses()

	if dropped and DataClient:GetData({ "Day", "Phase" }, "Session") == "Summary" then
		self:Commit()
	end
end

function MenuHandler.PaintCell(self: MenuHandler, cell: Frame, recipe: Recipes.RecipeEntry, selectable: boolean): ()
	cell:SetAttribute("RecipeId", recipe.id)
	-- Named after what it holds so the tutorial can point at one dish by path.
	cell.Name = recipe.id
	cell.Visible = true

	SetPair(cell:FindFirstChild("Txt"), recipe.name)
	SetPair(resolve(cell, { "Price", "Price" }), UIHandler:FormatNumber(recipe.price))

	local icon = cell:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		FoodPreview.Show(icon, recipe)
	end

	local locked = cell:FindFirstChild("Locked")
	if locked and locked:IsA("GuiObject") then
		locked.Visible = not selectable
	end

	local picked = self.Selected[recipe.id] == true
	local background = cell:FindFirstChild("Bg")
	if background and background:IsA("GuiObject") then
		if background:GetAttribute("UnselectedColor") == nil then
			background:SetAttribute("UnselectedColor", background.BackgroundColor3)
		end
		background.BackgroundColor3 = if picked
			then Color3.fromRGB(196, 242, 170)
			else background:GetAttribute("UnselectedColor") :: Color3
	end
	local stroke = background and background:FindFirstChildOfClass("UIStroke")
	if stroke then
		if stroke:GetAttribute("UnselectedThickness") == nil then
			stroke:SetAttribute("UnselectedThickness", stroke.Thickness)
		end
		stroke.Color = if picked then CELL_STROKE_PICKED else CELL_STROKE_IDLE
		stroke.Thickness = if picked then 4 else stroke:GetAttribute("UnselectedThickness") :: number
	end

	-- A punch the moment it lands on the menu, so the pick is felt and not only seen.
	if picked and cell:GetAttribute("Picked") ~= true then
		Animate.Pop(cell)
	end

	cell:SetAttribute("Picked", picked)
end

function MenuHandler.RefreshFilters(self: MenuHandler): ()
	for _, filter in FILTERS do
		local tab = self.Filters[filter.Name]
		local background = tab and tab:FindFirstChild("Bg")
		if background and background:IsA("Frame") then
			background.BackgroundColor3 = if filter.Station == self.Filter then FILTER_ON else FILTER_OFF
		end
	end
end

function MenuHandler.RefreshPicked(self: MenuHandler): ()
	local menu = self:GetSelection()
	table.sort(menu)

	for index, slot in self.PickedSlots do
		local recipeId = menu[index]
		local recipe = recipeId and Recipes:Get(recipeId)
		-- The plate springs in only when the place goes from empty to filled.
		local arriving = recipe ~= nil and not slot.Filled.Visible

		slot.Filled.Visible = recipe ~= nil
		slot.Empty.Visible = recipe == nil

		-- A scale, not a slide: these plates are placed by a list layout, which owns their position.
		if arriving then
			Animate.Pop(slot.Filled)
		end

		if recipe then
			SetPair(slot.Filled:FindFirstChild("Txt"), recipe.name)

			local icon = slot.Filled:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				FoodPreview.Show(icon, recipe)
			end
		end
	end

	SetPair(resolve(self.Screen, CAPACITY_PATH), `{#menu}/{DayCycleConfig.MenuMax} Selected`)
end

--- Both menu bonuses are all-or-nothing: one qualifying dish on the menu earns the whole line.
function MenuHandler.RefreshBonuses(self: MenuHandler): ()
	local bonuses = self.Bonuses
	if not bonuses then
		return
	end

	local earned: { [string]: boolean } = { Vegan = false, GlutenFree = false }

	for recipeId in self.Selected do
		local recipe = Recipes:Get(recipeId)
		if not recipe then
			continue
		end

		earned.Vegan = earned.Vegan or recipe.vegan
		earned.GlutenFree = earned.GlutenFree or recipe.glutenFree
	end

	for key, pair in bonuses do
		if pair.On then
			pair.On.Visible = earned[key]
		end
		if pair.Off then
			pair.Off.Visible = not earned[key]
		end
	end
end

function MenuHandler.CountSelected(self: MenuHandler): number
	local count = 0

	for _ in self.Selected do
		count += 1
	end

	return count
end

function MenuHandler.ToggleRecipe(self: MenuHandler, recipeId: string): ()
	if DataClient:GetData({ "Day", "Phase" }, "Session") ~= "Summary" then
		UIHandler:Toast("Tomorrow's menu is planned after closing")
		return
	end

	local recipe = Recipes:Get(recipeId)
	local level = DataClient:GetData({ "Level" }) or 1
	if not recipe or recipe.unlockLevel > level then
		UIHandler:Toast(if recipe then `Unlocks at level {recipe.unlockLevel}` else "Unknown recipe")
		return
	end

	if not HasStation(recipe.station) then
		UIHandler:Toast(`Needs a {recipe.station} - buy it in Upgrades`)
		return
	end

	if self.Selected[recipeId] then
		self.Selected[recipeId] = nil
	else
		if self:CountSelected() >= DayCycleConfig.MenuMax then
			UIHandler:Toast(`No more than {DayCycleConfig.MenuMax} recipes on the menu`)
			return
		end

		self.Selected[recipeId] = true
	end

	self:Rebuild()
	self:Commit()
end

-- Every evening pick is sent right away so the server remains the draft's authority.
function MenuHandler.Commit(self: MenuHandler): ()
	Bus.Day.SelectMenu:Fire(self:GetSelection())
end

function MenuHandler.GetSelection(self: MenuHandler): { string }
	local menu = {}

	for recipeId in self.Selected do
		menu[#menu + 1] = recipeId
	end

	return menu
end

function MenuHandler.NextDay(self: MenuHandler): ()
	if DataClient:GetData({ "Day", "Phase" }, "Session") ~= "Summary" then
		return
	end
	if self:CountSelected() < DayCycleConfig.MenuMin then
		Pages.Open(Pages.Names.Inventory)
		UIHandler:Toast(`Pick at least {DayCycleConfig.MenuMin} recipes`)
		return
	end

	-- The page stays locked until replicated Phase confirms that the server accepted the transition.
	Bus.Day.Next:Fire()
end

export type BonusPair = { On: GuiObject?, Off: GuiObject? }
export type PickedSlot = { Filled: Frame, Empty: Frame }

export type MenuHandler = typeof(MenuHandler) & {
	Janitor: any,
	Screen: ScreenGui,
	Grid: Instance,
	PickedStrip: Instance,
	Cells: { Frame },
	PickedSlots: { PickedSlot },
	Filters: { [string]: GuiObject },
	Bonuses: { [string]: BonusPair }?,
	Selected: { [string]: boolean },
	Filter: string?,
}

return MenuHandler :: MenuHandler
