--!strict
-- Upgrade screen: three category trees, a node is bought only after the one it grows from.
--
-- Drives the Upgrades screen authored in StarterGui. Nothing is built here: the tree, the connector
-- lines and the footer are all drawn in the editor, and this handler only says which upgrade sits in
-- which slot, what each slot looks like right now, and what the footer reads.
--
-- UpgradeTree maps individual purchase levels to the original game's twelve positions.
-- The registry remains responsible for saved IDs, prices, stats and purchase requirements.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Authored = require(_Shared.UI.Authored)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local GameTypes = require(_Shared.GameTypes)
local Press = require(_Shared.UI.Press)
local UIHandler = require(_Handlers.UIHandler)
local Upgrades = require(_Configs.Registries.Upgrades)
local TreeConfig = require(_Configs.UpgradeTree)

--[[ Constants ]]--
local SCREEN_NAME = "Upgrades"
local MAIN_PATH = { "MainFrame", "Main" }
-- Keep the authored edge spacing only while the wider tree needs horizontal scrolling.
local TREE_SCROLL_PADDING = 12

-- Category tabs, in the order they are drawn.
local TABS: { { Name: string, Category: GameTypes.UpgradeCategory } } = {
	{ Name = "Store", Category = "Cafe" },
	{ Name = "Kitchen", Category = "Kitchen" },
	{ Name = "GreenHouse", Category = "Garden" },
}

-- Original ItemNumber -> authored cell. A saved upgrade can occupy several purchase-level cells.
local SLOTS = TreeConfig.Slots

-- Every authored box. Rows use fixed centered positions so hover scaling cannot move neighbors.
-- Unclaimed slots are hidden without moving the remaining nodes or their connectors.
local ALL_SLOTS: { { string } } = {
	{ "TopSlot" },
	{ "FinalSlot" },
	{ "SlotL" },
	{ "SlotR" },
	{ "Row3L", "Slot1" },
	{ "Row3L", "Slot2" },
	{ "Row3R", "Slot1" },
	{ "Row3R", "Slot2" },
	{ "Row4L", "Slot1" },
	{ "Row4L", "Slot2" },
	{ "Row4R", "Slot1" },
	{ "Row4R", "Slot2" },
}

-- The one node the artist drew contents into; every other box borrows its icon.
local ICON_TEMPLATE = { "Row4L", "Slot1", "Icon" }

-- Node paint per state. The cream and the green are the authored ones, the rest follow from them.
local BOX_COLOR: { [string]: Color3 } = {
	Owned = Color3.fromRGB(253, 234, 195),
	Ready = Color3.fromRGB(253, 234, 195),
	Poor = Color3.fromRGB(253, 234, 195),
	Locked = Color3.fromRGB(202, 191, 172),
	Empty = Color3.fromRGB(160, 154, 145),
}
local STROKE_COLOR: { [string]: Color3 } = {
	Owned = Color3.fromRGB(34, 169, 0),
	Ready = Color3.fromRGB(240, 176, 76),
	Poor = Color3.fromRGB(168, 78, 62),
	Locked = Color3.fromRGB(120, 116, 108),
	Empty = Color3.fromRGB(120, 116, 108),
}
local ICON_TRANSPARENCY: { [string]: number } = {
	Owned = 0,
	Ready = 0,
	Poor = 0.2,
	Locked = 0.6,
	Empty = 1,
}
-- The authored stroke is hairline, so the selected node is called out by its fill instead.
local SELECTED_BOX = Color3.fromRGB(255, 255, 255)
local SELECTED_STROKE_SCALE = 3

local TAB_ON = Color3.fromRGB(255, 255, 255)
local TAB_OFF = Color3.fromRGB(168, 163, 156)

--[[ Tables ]]--
local ShopHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
local resolve = Authored.Resolve

-- Most slots are the coloured box themselves; the one the artist detailed wraps its box in a
-- transparent frame and puts the icon beside it. Both shapes end up as (box, slot).
local function BoxOf(slot: Instance): Frame?
	if slot:FindFirstChildOfClass("UICorner") then
		return slot :: Frame
	end

	return slot:FindFirstChildOfClass("Frame")
end

local function SlotKey(path: { string }): string
	return table.concat(path, ".")
end

-- What the player can do with this node right now.
local function GetState(
	entry: Upgrades.UpgradeEntry,
	targetLevel: number,
	levels: { [string]: number },
	playerLevel: number,
	cash: number
): string
	local level = levels[entry.id] or 0
	if level >= targetLevel then
		return "Owned"
	end

	local missing = Upgrades:GetMissingRequirement(entry, levels)
	if missing or playerLevel < entry.unlockLevel or level + 1 < targetLevel then
		return "Locked"
	end

	local cost = Upgrades:GetCost(entry.id, level)

	return if cost and cash >= cost then "Ready" else "Poor"
end

-- The line under the name: what the upgrade does, plus how far it has been taken or why it is shut.
local function GetDetail(
	entry: Upgrades.UpgradeEntry,
	state: string,
	level: number,
	targetLevel: number,
	levels: { [string]: number }
): string
	if state == "Locked" then
		if level + 1 < targetLevel then
			return `{entry.blurb}\nBuy {Upgrades:GetDisplayName(entry.id, targetLevel - 2)} ({targetLevel - 1}/{entry.maxLevel}) first`
		end
		local missing = Upgrades:GetMissingRequirement(entry, levels)
		local parentEntry = missing and Upgrades:Get(missing)
		local reason = if parentEntry then `Buy {parentEntry.name} first` else `Unlocks at level {entry.unlockLevel}`

		return `{entry.blurb}\n{reason}`
	end

	return `{entry.blurb}\nLevel {targetLevel}/{entry.maxLevel}`
end

--[[ Handling ]]--
function ShopHandler.OnStart(self: ShopHandler): ()
	local screen = UIHandler:GetPanel(SCREEN_NAME)
	local main = screen and resolve(screen, MAIN_PATH)
	if not screen or not main then
		warn(`[ShopHandler] '{SCREEN_NAME}' is missing; the upgrade tree is disabled`)
		return
	end

	local content = resolve(main, { "Tree", "Content" })
	local bottom = main:FindFirstChild("Bottom")
	if not content or not bottom then
		warn(`[ShopHandler] '{SCREEN_NAME}' has no tree to drive; the upgrade tree is disabled`)
		return
	end

	self.Content = content
	self.Bottom = bottom
	self.Slots = {}
	self.Tabs = {}
	self.Selected = {}
	self.Category = TABS[1].Category

	self:CollectSlots()
	self:BindTabs(main)
	self:BindPurchase()

	DataClient:WaitForData()
	self:ShowCategory(self.Category)
	local tree = content.Parent
	if tree and tree:IsA("ScrollingFrame") then
		local treeContent = content :: GuiObject
		local lifetime = Janitor.new()
		lifetime:LinkToInstance(tree)
		local function centerTree(): ()
			local width = Authored.UnscaledSize(treeContent).X
			if tree.AbsoluteSize.X <= 0 then
				return
			end
			local viewportWidth = Authored.UnscaledSize(tree).X * tree.AbsoluteWindowSize.X / tree.AbsoluteSize.X
			local fits = width <= viewportWidth
			local left = if fits then (viewportWidth - width) / 2 else TREE_SCROLL_PADDING
			local position = treeContent.Position
			treeContent.Position = UDim2.new(0, left, position.Y.Scale, position.Y.Offset)
			tree.CanvasPosition = Vector2.new(if fits then 0 else (width - viewportWidth) / 2 + left, 0)
		end
		lifetime:Add(tree:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(centerTree), "Disconnect")
		centerTree()
	end

	DataClient:SubscribeToPath({ "Base", "Upgrades" }, function()
		self:Refresh()
	end, "Cloud", true)

	DataClient:SubscribeToPath({ "Cash" }, function()
		self:Refresh()
	end, "Cloud")

	DataClient:SubscribeToPath({ "Level" }, function()
		self:Refresh()
	end, "Cloud")
end

--- Finds every authored box once and gives the ones without artwork the icon the artist drew.
function ShopHandler.CollectSlots(self: ShopHandler): ()
	local iconTemplate = resolve(self.Content, ICON_TEMPLATE) :: ImageLabel?

	for _, path in ALL_SLOTS do
		local slot = resolve(self.Content, path)
		local box = slot and BoxOf(slot)
		if not slot or not slot:IsA("GuiObject") or not box then
			warn(`[ShopHandler] no slot at '{SlotKey(path)}'`)
			continue
		end

		local icon = slot:FindFirstChild("Icon") :: ImageLabel?
		if not icon and iconTemplate then
			local clone = iconTemplate:Clone()
			clone.Parent = slot
			icon = clone
		end

		local stroke = box:FindFirstChildOfClass("UIStroke")
		local node: Node = {
			Slot = slot,
			Box = box,
			Icon = icon,
			Stroke = stroke,
			Thickness = if stroke then stroke.Thickness else 0,
			UpgradeId = nil,
			PurchaseLevel = 1,
			Selected = false,
			State = nil,
		}

		-- A box is its own click target: the drawing has no button inside it, and adding one would
		-- be layout built in code.
		-- Scale the whole node so sibling artwork follows the same centered motion.
		Animate.Press(box, slot)
		Press.BindTap(box, function()
			local upgradeId = node.UpgradeId
			if upgradeId then
				self:Select(SlotKey(path))
			end
		end)

		self.Slots[SlotKey(path)] = node
	end
end

function ShopHandler.BindTabs(self: ShopHandler, main: Instance): ()
	local top = main:FindFirstChild("Top")
	if not top then
		warn("[ShopHandler] the category tabs are missing")
		return
	end

	for _, tab in TABS do
		local button = top:FindFirstChild(tab.Name)
		if not button or not button:IsA("GuiButton") then
			warn(`[ShopHandler] no category tab named '{tab.Name}'`)
			continue
		end

		self.Tabs[tab.Category] = button
		Animate.Press(button)
		button.Activated:Connect(function()
			self:ShowCategory(tab.Category)
		end)
	end
end

--- The footer's Purchase plate is a frame, so the press is read off it directly.
function ShopHandler.BindPurchase(self: ShopHandler): ()
	local buy = resolve(self.Bottom, { "Status", "Prchased" })
	if not buy or not buy:IsA("GuiObject") then
		warn("[ShopHandler] the footer has no purchase plate")
		return
	end

	self.BuyPlate = buy

	Animate.Press(buy)
	Press.BindTap(buy, function()
		self:Buy()
	end)
end

--- Puts one category's upgrades into the authored boxes and repaints everything.
function ShopHandler.ShowCategory(self: ShopHandler, category: GameTypes.UpgradeCategory): ()
	self.Category = category
	for _, child in self.Content:GetChildren() do
		if not child:IsA("GuiObject") then
			continue
		end
		local connectorCategory = child:GetAttribute("UpgradeCategory")
		if connectorCategory then
			child.Visible = connectorCategory == category
		elseif child.Name == "GreenhouseConnectors" then
			child.Visible = category == "Garden"
		elseif child:GetAttribute("GardenLegacyConnectorVisible") ~= nil then
			child.Visible = false
		end
	end

	for _, node in self.Slots do
		node.UpgradeId = nil
	end

	for index, purchase in TreeConfig.Categories[category] do
		local path = SLOTS[index]
		local node = path and self.Slots[SlotKey(path)]

		if not node then
			warn(`[ShopHandler] No authored slot for {purchase.Id} level {purchase.Level}`)
			continue
		end

		node.UpgradeId = purchase.Id
		node.PurchaseLevel = purchase.Level
	end

	for name, tab in self.Tabs do
		local background = tab:FindFirstChild("Bg")
		if background and background:IsA("ImageLabel") then
			background.ImageColor3 = if name == category then TAB_ON else TAB_OFF
		end
	end

	-- The footer must not keep talking about a node from another tab.
	if not self.Selected[category] then
		self.Selected[category] = SlotKey(SLOTS[0])
	end

	self:Refresh()
end

function ShopHandler.Select(self: ShopHandler, slotKey: string): ()
	self.Selected[self.Category] = slotKey
	self:Refresh()
end

function ShopHandler.Refresh(self: ShopHandler): ()
	local levels = DataClient:GetData({ "Base", "Upgrades" }) or {}
	local playerLevel = DataClient:GetData({ "Level" }) or 1
	local cash = DataClient:GetData({ "Cash" }) or 0
	local selected = self.Selected[self.Category]

	for key, node in self.Slots do
		local entry = node.UpgradeId and Upgrades:Get(node.UpgradeId)
		node.Slot.Visible = entry ~= nil
		node.Box.Active = entry ~= nil
		node.Box.Selectable = entry ~= nil
		node.Box.Interactable = entry ~= nil
		node.Slot:SetAttribute("UpgradeId", node.UpgradeId)
		node.Slot:SetAttribute("PurchaseLevel", if entry then node.PurchaseLevel else nil)
		local state = if entry then GetState(entry, node.PurchaseLevel, levels, playerLevel, cash) else "Empty"

		self:PaintNode(node, state, entry ~= nil and key == selected)
		local label = node.Slot:FindFirstChild("UpgradeName")
		if label and label:IsA("TextLabel") then
			label.Text = if entry then Upgrades:GetDisplayName(entry.id, node.PurchaseLevel - 1) else ""
			if entry and entry.maxLevel > 1 and not entry.names then
				label.Text ..= `\n{node.PurchaseLevel}/{entry.maxLevel}`
			end
		end
	end

	self:RefreshFooter(levels, playerLevel, cash)
end

function ShopHandler.PaintNode(_self: ShopHandler, node: Node, state: string, isSelected: boolean): ()
	-- A node punches when it becomes the selected one, and again when it is finally owned.
	local becameSelected = isSelected and not node.Selected
	local becameOwned = state == "Owned" and node.State ~= "Owned" and node.State ~= nil
	if becameSelected or becameOwned then
		Animate.Pop(node.Slot)
	end

	node.Selected = isSelected
	node.State = state
	node.Box.BackgroundColor3 = if isSelected then SELECTED_BOX else BOX_COLOR[state]

	local stroke = node.Stroke
	if stroke then
		stroke.Color = STROKE_COLOR[state]
		stroke.Thickness = if isSelected then node.Thickness * SELECTED_STROKE_SCALE else node.Thickness
	end

	local label = node.Slot:FindFirstChild("UpgradeName")
	local icon = node.Icon
	if icon then
		icon.Visible = label == nil
		icon.ImageTransparency = ICON_TRANSPARENCY[state]
	end
end

function ShopHandler.RefreshFooter(
	self: ShopHandler,
	levels: { [string]: number },
	playerLevel: number,
	cash: number
): ()
	local bottom = self.Bottom
	local funds = resolve(bottom, { "Funds", "Main", "Value" })

	-- Funds count down to what is left after a purchase instead of snapping to it.
	if funds then
		Animate.Count(funds, cash, function(value: number)
			Authored.SetPair(funds, UIHandler:FormatNumber(value))
		end, 2)
	end

	local key = self.Selected[self.Category]
	local node = key and self.Slots[key]
	local entry = node and node.UpgradeId and Upgrades:Get(node.UpgradeId)
	if not entry then
		Authored.SetPair(resolve(bottom, { "Label1", "Txt" }), "Pick an upgrade")
		Authored.SetPair(resolve(bottom, { "Label2", "Value" }), "")
		self:SetDesc("Tap a node to see what it does.")
		self:ShowStatus(nil, "")
		return
	end

	local level = levels[entry.id] or 0
	local targetLevel = (node :: Node).PurchaseLevel
	local state = GetState(entry, targetLevel, levels, playerLevel, cash)
	local cost = if state == "Owned" then nil else Upgrades:GetCost(entry.id, targetLevel - 1)

	Authored.SetPair(resolve(bottom, { "Label1", "Txt" }), Upgrades:GetDisplayName(entry.id, targetLevel - 1))
	Authored.SetPair(resolve(bottom, { "Label2", "Value" }), if cost then UIHandler:FormatNumber(cost) else "-")
	self:SetDesc(GetDetail(entry, state, level, targetLevel, levels))

	if state == "Owned" then
		self:ShowStatus("Purchased", "Purchased")
	elseif state == "Ready" then
		self:ShowStatus("Prchased", "Purchase")
	elseif state == "Poor" then
		self:ShowStatus("Locked", "Not enough")
	else
		local blockedByParent = Upgrades:GetMissingRequirement(entry, levels) ~= nil or level + 1 < targetLevel

		self:ShowStatus("Locked", if blockedByParent then "Locked" else `Lv. {entry.unlockLevel}+`)
	end
end

function ShopHandler.SetDesc(self: ShopHandler, text: string): ()
	local desc = self.Bottom:FindFirstChild("Desc")
	if desc and desc:IsA("TextLabel") then
		desc.Text = text
	end
end

--- One of the three authored status plates is up at a time; the others go dark.
function ShopHandler.ShowStatus(self: ShopHandler, plateName: string?, text: string): ()
	local status = self.Bottom:FindFirstChild("Status")
	if not status then
		return
	end

	for _, plate in status:GetChildren() do
		if not plate:IsA("GuiObject") then
			continue
		end

		local isCurrent = plate.Name == plateName
		-- Springs in when the footer switches from one state plate to another.
		local arriving = isCurrent and not plate.Visible

		plate.Visible = isCurrent

		if isCurrent then
			Authored.SetPair(plate:FindFirstChild("Txt"), text)

			if arriving then
				Animate.Enter(plate)
			end
		end
	end
end

function ShopHandler.Buy(self: ShopHandler): ()
	local key = self.Selected[self.Category]
	local node = key and self.Slots[key]
	if node and node.UpgradeId and node.State == "Ready" then
		Bus.Progress.BuyUpgrade:Fire(node.UpgradeId, node.PurchaseLevel)
	end
end

export type Node = {
	Slot: GuiObject,
	Box: Frame,
	Icon: ImageLabel?,
	Stroke: UIStroke?,
	Thickness: number,
	UpgradeId: string?,
	PurchaseLevel: number,
	-- What the node looked like last time it was painted, so a change can be felt as well as seen.
	Selected: boolean?,
	State: string?,
}

export type ShopHandler = typeof(ShopHandler) & {
	Content: Instance,
	Bottom: Instance,
	BuyPlate: GuiObject?,
	Slots: { [string]: Node },
	Tabs: { [string]: GuiButton },
	Selected: { [string]: string? },
	Category: GameTypes.UpgradeCategory,
}

return ShopHandler :: ShopHandler
