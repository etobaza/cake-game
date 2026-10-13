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
-- Dishes guests are waiting for list first and carry a generated "N waiting" badge.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local FoodPreview = require(_Shared.UI.FoodPreview)
local IngredientCard = require(_Shared.UI.IngredientCard)
local IngredientChip = require(_Shared.UI.IngredientChip)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local Buildings = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local DayCycleConfig = require(_Configs.DayCycle)
local Ingredients = require(_Configs.Registries.Ingredients)
local GuestOrders = require(_Shared.GuestOrders)
local OrdersConfig = require(_Configs.Orders)
local Pages = require(_Shared.UI.Stores.Pages)
local Press = require(_Shared.UI.Press)
local Recipes = require(_Configs.Registries.Recipes)
local RecipeRequirements = require(_Shared.RecipeRequirements)
local RequirementLabel = require(_Shared.UI.RecipeRequirementLabel)
local Theme = require(_Shared.UI.Theme)
local TutorialPolicy = require(_Shared.TutorialPolicy)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local SCREEN_NAME = "RecipeToCook"
-- Start closes the page once the server confirms the pick; a refused pick keeps it open.
local CLOSE_WAIT_SECONDS = 5
local ROWS_PATH = { "MainFrame", "Container", "Content" }
local CARD_NAME = "Cooking"
local CHIPS_NAME = "Items"
local LIST_EDGE_PADDING = 8
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

local function PrepareList(content: ScrollingFrame, janitor: any): ()
	local layout = content:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end

	content.AnchorPoint = Vector2.zero
	content.Position = UDim2.fromOffset(0, 0)
	content.Size = UDim2.fromScale(1, 1)
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Rows already reserve horizontal space in their authored width. Keep their
	-- outer strokes inside the scrolling clip at both ends of the list as well.
	local existingPadding = content:FindFirstChildOfClass("UIPadding")
	local padding = existingPadding or Instance.new("UIPadding")
	if not existingPadding then
		padding.Parent = content
		janitor:Add(padding, "Destroy")
	end
	padding.PaddingTop = UDim.new(0, LIST_EDGE_PADDING)
	padding.PaddingBottom = UDim.new(0, LIST_EDGE_PADDING)
	padding.PaddingLeft = UDim.new(0, 0)
	padding.PaddingRight = UDim.new(0, 0)

	local function refreshCanvas(): ()
		local height = content.AbsoluteSize.Y
		if height <= 0 then
			return
		end
		local scale = Authored.UnscaledSize(content).Y / height
		content.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y * scale + LIST_EDGE_PADDING * 2)
	end
	janitor:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas), "Disconnect")
	janitor:Add(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshCanvas), "Disconnect")
	refreshCanvas()
end

local function PantryCount(ingredientId: string): number
	return DataClient:GetData({ "Pantry", ingredientId }) or 0
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
	for index = 1, IngredientCard.MostIngredients() do
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

local function SelectedRecipe(): Recipes.RecipeEntry?
	local recipeId = DataClient:GetData({ "Cooking", "SelectedRecipeId" }, "Session")

	return if typeof(recipeId) == "string" then Recipes:Get(recipeId) else nil
end

-- Today's menu, as the mixer sees it: coffee and anything else that starts elsewhere is left out.
-- During the introduction only its dish is offered, so the first bake cannot wander off.
local function MixerMenu(): { Recipes.RecipeEntry }
	local menu = DataClient:GetData({ "Day", "Menu" }, "Session") or {}
	local cloud = DataClient:GetData({}, "Cloud")
	local session = DataClient:GetData({}, "Session")
	local only = if cloud and session and TutorialPolicy.IsActive(cloud) then TutorialPolicy.Recipe(session) else nil
	local offered = {}

	for index = 1, #menu do
		local recipe = Recipes:Get(menu[index])
		if recipe and Recipes:GetStartStation(recipe) == STATION_KIND and (not only or recipe.id == only) then
			offered[#offered + 1] = recipe
		end
	end

	return offered
end

-- One layer of the waiting pill. Every layer carries the same text so they auto-size to one width;
-- only the top layer shows it. A UIGradient tints a TextLabel's lettering too, so the gradient fill
-- and the white text cannot share a layer.
local function badgeLayer(name: string, fill: Color3, zIndex: number, edged: boolean): TextLabel
	local style = OrdersConfig.WaitingBadge
	local layer = Instance.new("TextLabel")
	layer.Name = name
	layer.AutomaticSize = Enum.AutomaticSize.X
	layer.Size = UDim2.fromOffset(0, style.Height)
	layer.BackgroundColor3 = fill
	layer.BorderSizePixel = 0
	layer.FontFace = Theme.Fonts.ExtraBold
	layer.TextSize = style.TextSize
	layer.ZIndex = zIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Corners.Pill
	corner.Parent = layer
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, style.Padding)
	padding.PaddingRight = UDim.new(0, style.Padding)
	padding.Parent = layer
	if edged then
		local edge = Instance.new("UIStroke")
		edge.Color = style.EdgeColor
		edge.Thickness = style.Edge
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = layer
	end
	return layer
end

-- A chunky pill in the row's top-left corner, above the dish icon: how many guests wait for this
-- dish. A darker plate sits under a gradient face, the lettering is outlined, and the pill breathes
-- so a waiting guest is hard to miss.
local function buildWaitingBadge(row: Frame, janitor: Janitor.Janitor): Frame
	local style = OrdersConfig.WaitingBadge
	local badge = Instance.new("Frame")
	badge.Name = "Waiting"
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Position = UDim2.fromOffset(style.Inset.X, style.Inset.Y)
	badge.Size = UDim2.fromOffset(0, style.Height + style.Depth)
	badge.BackgroundTransparency = 1
	badge.Visible = false
	badge.ZIndex = style.ZIndex

	local plate = badgeLayer("Plate", style.EdgeColor, style.ZIndex, true)
	plate.Position = UDim2.fromOffset(0, style.Depth)
	plate.TextTransparency = 1
	plate.Parent = badge

	local face = badgeLayer("Face", Color3.new(1, 1, 1), style.ZIndex + 1, true)
	face.TextTransparency = 1
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(style.ColorTop, style.Color)
	gradient.Rotation = 90
	gradient.Parent = face
	face.Parent = badge

	local label = badgeLayer("Label", Color3.new(1, 1, 1), style.ZIndex + 2, false)
	label.BackgroundTransparency = 1
	label.TextColor3 = style.TextColor
	local outline = Instance.new("UIStroke")
	outline.Color = style.EdgeColor
	outline.Thickness = style.TextOutline
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = label
	label.Parent = badge

	local scale = Instance.new("UIScale")
	scale.Parent = badge
	local pulse = TweenService:Create(
		scale,
		TweenInfo.new(style.PulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = style.PulseScale }
	)
	janitor:Add(function(): ()
		pulse:Cancel()
		pulse:Destroy()
	end, true)
	pulse:Play()

	badge.Parent = row
	return badge
end

local function setWaitingBadge(badge: Frame, count: number): ()
	badge.Visible = count > 0
	for _, layer in badge:GetChildren() do
		if layer:IsA("TextLabel") then
			layer.Text = `{count} waiting`
		end
	end
end

--[[ Handling ]]--
function RecipePickHandler.OnStart(self: RecipePickHandler): ()
	local screen = UIHandler:GetPanel(SCREEN_NAME)
	local content = screen and resolve(screen, ROWS_PATH)
	if not screen or not content or not content:IsA("ScrollingFrame") then
		print(`[RecipePickHandler] '{SCREEN_NAME}' is missing; the station pick is disabled`)
		return
	end

	self.Screen = screen
	self.Janitor = Janitor.new()
	self.Content = content
	self.Rows = {}
	self.Badges = {}
	self.RequirementLabels = {}
	self.Chips = {}
	self.NeededChips = {}

	PrepareList(content, self.Janitor)
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
	-- Finishing the introduction opens the whole menu again.
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Tutorial", "Status" }, function()
			self:Refresh()
		end, "Cloud", true),
		"Disconnect"
	)
	for _, path in { { "Pantry" }, { "Garden" } } do
		self.Janitor:Add(
			DataClient:SubscribeToPath(path, function()
				self:RefreshCard()
			end, "Cloud", true),
			"Disconnect"
		)
	end
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Base", "Upgrades" }, function(): ()
			self:Refresh()
		end, "Cloud", true),
		"Disconnect"
	)

	-- The tutorial's guest and progress decide whether the menu is limited to its dish.
	-- Guests' orders reorder the list and set the waiting badges.
	for _, path in { { "Day", "Menu" }, { "Cooking" }, { "Stations" }, { "Tutorial" }, { "Customers" } } do
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
		print("[RecipePickHandler] the recipe list has no rows to fill")
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
		local requirement = RequirementLabel.Create(row, true)
		self.RequirementLabels[row] = requirement
		self.Janitor:Add(requirement, "Destroy")
		self.Badges[row] = buildWaitingBadge(row, self.Janitor)
		self.Janitor:Add(self.Badges[row], "Destroy")
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
						self.CloseOnPick = { RecipeId = recipeId, Until = os.clock() + CLOSE_WAIT_SECONDS }
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
		print("[RecipePickHandler] the cooking card is missing; only the list is shown")
		return
	end

	-- Detached copies first: the drawn chips themselves are cleared away when the pairs are built.
	local doneTemplate, notDoneTemplate = IngredientCard.Templates(holder)
	if not doneTemplate or not notDoneTemplate then
		print("[RecipePickHandler] the cooking card has no chips to reuse")
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

	-- The unlit template also draws the per-row "needed" chips.
	self.NeededTemplate = notDoneTemplate
	self.Janitor:Add(notDoneTemplate, "Destroy")

	-- The card scrolls, so its chips commit only on a tap that stayed in place.
	self.Chips = IngredientCard.BuildChips(
		holder,
		doneTemplate,
		notDoneTemplate,
		IngredientCard.MostIngredients(),
		self.Janitor,
		{ StationId = MIXER_ID, PantryCount = PantryCount, Floating = false }
	)
	doneTemplate:Destroy()
end

function RecipePickHandler.Refresh(self: RecipePickHandler): ()
	self:RefreshRows()
	self:RefreshCard()
	self:CloseAfterPick()
end

-- The player only came to pick a dish: once the mixer has the one they started, the page closes and
-- the ingredients shown above the mixer take over.
function RecipePickHandler.CloseAfterPick(self: RecipePickHandler): ()
	local pending = self.CloseOnPick
	if not pending then
		return
	end
	if os.clock() > pending.Until then
		self.CloseOnPick = nil
		return
	end
	local selected = SelectedRecipe()
	if not selected or selected.id ~= pending.RecipeId then
		return
	end
	self.CloseOnPick = nil
	if Pages.Current:peek() == Pages.Names.RecipeToCook then
		Pages.Close()
	end
end

function RecipePickHandler.RefreshRows(self: RecipePickHandler): ()
	local selected = SelectedRecipe()
	local menu = MixerMenu()
	local waiting = GuestOrders.CountWaiting(DataClient:GetData({ "Customers" }, "Session"))
	-- Dishes guests wait for come first, most wanted on top; the rest keep the menu's order.
	local order: { [string]: number } = {}
	for index, recipe in menu do
		order[recipe.id] = index
	end
	table.sort(menu, function(left: Recipes.RecipeEntry, right: Recipes.RecipeEntry): boolean
		local leftCount, rightCount = waiting[left.id] or 0, waiting[right.id] or 0
		if leftCount ~= rightCount then
			return leftCount > rightCount
		end
		return order[left.id] < order[right.id]
	end)

	for index, row in self.Rows do
		local recipe = menu[index]
		local badge = self.Badges[row]
		local count = if recipe then waiting[recipe.id] or 0 else 0
		if badge then
			setWaitingBadge(badge, count)
		end
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
	RequirementLabel.Show(
		self.RequirementLabels[row],
		RecipeRequirements.GetMissing(recipe, DataClient:GetData({ "Base", "Upgrades" }) or {})
	)
	local needed = IngredientCard.Sorted(recipe)
	for index, chip in (self.NeededChips[row] or {}) :: { Frame } do
		local entry = needed[index]
		chip.Visible = entry ~= nil
		if not entry then
			continue
		end
		local name = IngredientCard.Name(entry.Id)
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

	local loaded = IngredientCard.Loaded(DataClient:GetData({ "Stations" }, "Session"), STATION_KIND)
	local needed = IngredientCard.Sorted(recipe)
	local hints = {}
	local cloud = DataClient:GetData({})

	for index, chip in self.Chips do
		local entry = needed[index]
		if not entry then
			IngredientCard.HideChip(chip)
			continue
		end

		local have = loaded[entry.Id] or 0
		local complete = have >= entry.Amount
		if not complete and not Ingredients:IsInfinite(entry.Id) then
			hints[#hints + 1] = IngredientCard.SourceHint(entry.Id, cloud)
		end
		local text = `{IngredientCard.Name(entry.Id)} {math.min(have, entry.Amount)}/{entry.Amount}`
		IngredientCard.ShowChip(chip, entry.Id, text, complete)
	end
	IngredientCard.ShowHints(content:FindFirstChild("SourceHint"), hints)
end

function RecipePickHandler.Destroy(self: RecipePickHandler): ()
	local janitor = self.Janitor
	if janitor == nil then
		return
	end
	-- Janitor removes its metatable on destruction; release the owner before repeated cleanup.
	self.Janitor = nil
	janitor:Destroy()
end

export type ChipPair = IngredientCard.ChipPair

export type RecipePickHandler = typeof(RecipePickHandler) & {
	-- The Start press waiting for the server to select its recipe.
	CloseOnPick: { RecipeId: string, Until: number }?,
	RequirementLabels: { [Frame]: TextLabel },
	Screen: ScreenGui,
	Content: Instance,
	Rows: { Frame },
	-- Generated "N waiting" pill per row.
	Badges: { [Frame]: Frame },
	Card: ScrollingFrame?,
	CardContent: Frame?,
	Chips: { ChipPair },
	Janitor: any,
	NeededTemplate: Frame?,
	NeededChips: { [Frame]: { Frame } },
}

return RecipePickHandler :: RecipePickHandler
