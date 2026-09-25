--!strict
-- The one-slot hotbar. ToolViewHandler owns tools; TrayHandler owns food and ingredient/fuel visuals.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]
--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]
--
local FoodPreview = require(_Shared.UI.FoodPreview)
local Animate = require(_Shared.UI.Animate)
local BaseStats = require(_Configs.BaseStats)
local Buildings = require(_Configs.Buildings)
local DataClient = require(_Handlers.DataHandlerClient)
local Ingredients = require(_Configs.Registries.Ingredients)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(_Configs.Registries.Recipes)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]
--
local HOTBAR_NAME = "Hotbar"
-- Nothing upgrades HandsLimit, so the authored slots past it would stay dead forever.
local SLOT_COUNT = BaseStats.HandsLimit
local EMPTY_TRANSPARENCY = 0.6
-- Reuse an authored name line, or clone the number label in older layouts to keep its artwork.
local NAME_LABEL = "ItemName"
local NAME_SOURCE = "NumberOutside"
local NAME_SIZE = UDim2.new(1, -8, 0.34, 0)
local NAME_POSITION = UDim2.new(0.5, 0, 1, -3)
local NAME_ANCHOR = Vector2.new(0.5, 1)
local NAME_MIN_TEXT_SIZE = 10
local NAME_MAX_TEXT_SIZE = 16
local ICON_LABEL = "ImageLabel"
local TOOL_KIND = "Tool"
local FUEL_KIND = "Fuel"

--[[ Tables ]]
--
local HandsHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Types ]]
--
type Slot = {
	Frame: Frame,
	Background: ImageLabel,
	Icon: ImageLabel,
	Name: TextLabel,
	-- Remembered so the slot only pops when something lands in it, not on every refresh.
	Filled: boolean,
}

--[[ Private Functions ]]
--
local function DescribeItem(item: any): string
	if item.Kind == "Leftover" then
		return "Leftover Pastry"
	end
	if item.Kind == "Ingredient" then
		local ingredient = Ingredients:Get(item.Id)
		return if ingredient then ingredient.name else item.Id
	end

	if item.Kind == TOOL_KIND then
		return Buildings.ToolLabel(item.Id)
	end

	if item.Kind == FUEL_KIND then
		return Buildings.FuelLabel()
	end

	local recipe = Recipes:Get(item.Id)
	local name = if recipe then recipe.name else item.Id

	if item.Kind == "Dough" then
		return `{name} (raw)`
	end

	if item.Kind == "Burnt" then
		return `{name} (burnt)`
	end

	return name
end

-- Outlined labels come as a pair, the inner one repeating the text on top of the stroke.
local function SetSlotText(label: TextLabel, text: string): ()
	label.Text = text

	local inner = label:FindFirstChildWhichIsA("TextLabel")
	if inner then
		inner.Text = text
	end
end

local function FitNameLabel(label: TextLabel): ()
	label.Rotation = 0
	label.TextScaled = true
	label.TextSize = NAME_MAX_TEXT_SIZE
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.LineHeight = 1
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	constraint.Parent = label
	constraint.MinTextSize = NAME_MIN_TEXT_SIZE
	constraint.MaxTextSize = NAME_MAX_TEXT_SIZE
end

local function FindNameLabel(slot: Frame): TextLabel
	local label = slot:FindFirstChild(NAME_LABEL) :: TextLabel?
	if label then
		return label
	end

	local clone = (slot:FindFirstChild(NAME_SOURCE) :: TextLabel):Clone()
	clone.Name = NAME_LABEL
	clone.Parent = slot
	return clone
end

local function BuildName(slot: Frame): TextLabel
	local label = FindNameLabel(slot)
	-- Authored ItemName instances need the same normalization as freshly cloned numbers.
	label.AnchorPoint = NAME_ANCHOR
	label.Position = NAME_POSITION
	label.Size = NAME_SIZE
	label.Visible = false
	FitNameLabel(label)

	-- The clone brings the inner copy of the slot number along: it has to fill the new box.
	local inner = label:FindFirstChildWhichIsA("TextLabel")
	if inner then
		inner.AnchorPoint = Vector2.zero
		inner.Position = UDim2.fromScale(0, 0)
		inner.Size = UDim2.fromScale(1, 1)
		inner.FontFace = label.FontFace
		FitNameLabel(inner)
	end

	return label
end

--[[ Handling ]]
--
function HandsHandler.OnStart(self: HandsHandler): ()
	self.Janitor = Janitor.new()
	self.Slots = self:ResolveSlots()

	DataClient:WaitForData()
	self:Refresh()

	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Hands" }, function()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
end

-- Slots past the hand limit are hidden rather than left as empty decoration.
function HandsHandler.ResolveSlots(self: HandsHandler): { Slot }
	local hotbar = UIHandler:GetHud(HOTBAR_NAME) :: Frame
	local slots = {}

	for _, child in hotbar:GetChildren() do
		local index = tonumber(child.Name)
		if not index or not child:IsA("Frame") then
			continue
		end

		child.Visible = index <= SLOT_COUNT
		if not child.Visible then
			continue
		end

		slots[index] = {
			Frame = child,
			Background = child:FindFirstChild("Background") :: ImageLabel,
			Icon = child:FindFirstChild(ICON_LABEL) :: ImageLabel,
			Name = BuildName(child),
			Filled = false,
		}
		-- Reserve the lower third for the name instead of drawing it over the item preview.
		slots[index].Icon.Size = UDim2.fromScale(0.72, 0.54)
		local icon = slots[index].Icon
		self.Janitor:Add(function(): ()
			FoodPreview.Clear(icon)
		end)
	end

	return slots
end

-- Every carried item kind uses the shared preview dispatch, including tools and firewood.
function HandsHandler.RefreshHotbar(self: HandsHandler, hands: { any }): ()
	for index, slot in self.Slots do
		local item = hands[index]
		local filled = item ~= nil

		slot.Background.ImageTransparency = if filled then 0 else EMPTY_TRANSPARENCY
		FoodPreview.ShowItem(slot.Icon, item)
		slot.Name.Visible = filled

		if item then
			SetSlotText(slot.Name, DescribeItem(item))
		end

		if filled and not slot.Filled then
			Animate.Pop(slot.Frame)
		end

		slot.Filled = filled
	end
end

function HandsHandler.Refresh(self: HandsHandler): ()
	local hands = DataClient:GetData({ "Hands" }, "Session")
	if not hands or #hands == 0 then
		self:RefreshHotbar({})
		return
	end

	self:RefreshHotbar(hands)
end

function HandsHandler.Destroy(self: HandsHandler): ()
	self.Janitor:Destroy()
end

export type HandsHandler = typeof(HandsHandler) & {
	Slots: { Slot },
	Janitor: any,
}

return HandsHandler :: HandsHandler
