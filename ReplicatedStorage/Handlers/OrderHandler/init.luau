--!strict
-- Only seated guests place menu orders. Window shoppers buy stock without an order card.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Buildings = require(_Shared.Configs.Buildings)
local Authored = require(_Shared.UI.Authored)
local Card = require(script.Card)
local Config = require(_Shared.Configs.Orders)
local DataClient = require(_Handlers.DataHandlerClient)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local Tables = require(_Shared.Configs.TableMenus)
local UIHandler = require(_Handlers.UIHandler)

--[[ Tables ]]--
local OrderHandler = {
	dependencies = { "DataClient", "UIHandler" },
	priority = 80,
}

type Order = { CustomerId: string, Customer: any }

--[[ Private Functions ]]--
local function collectOrders(): { Order }
	local orders: { Order } = {}
	local customers = DataClient:GetData({ "Customers" }, "Session") or {}
	for customerId, customer in customers do
		if not customer.TableId then
			continue
		end
		if customer.State ~= "Choosing" and customer.State ~= "Waiting" then
			continue
		end
		orders[#orders + 1] = { CustomerId = customerId, Customer = customer }
	end
	table.sort(orders, function(left: Order, right: Order): boolean
		return (tonumber(left.CustomerId:match("_(%d+)$")) or 0) < (tonumber(right.CustomerId:match("_(%d+)$")) or 0)
	end)
	return orders
end

--[[ Handling ]]--
function OrderHandler.OnStart(self: OrderHandler): ()
	self.Janitor = Janitor.new()
	self.Cards = {}
	self.Accumulator = 0
	self.Root = UIHandler:GetHud("Order") :: Frame
	local container = self.Root:FindFirstChild("Container") :: Frame
	self.Template = (container:FindFirstChild("1") :: Frame):Clone()
	self.Janitor:Add(self.Template, "Destroy")
	-- Share the authored nameplate outside the scrolling clip. Card-sized text is unreadable.
	local tooltip = (self.Template:FindFirstChild("Header") :: Frame):Clone()
	tooltip.Name = "OrderTooltip"
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.Size = UDim2.fromOffset(Config.TooltipWidth, Config.TooltipHeight)
	tooltip.ZIndex = 10
	tooltip.Visible = false
	local background = tooltip:FindFirstChild("Background") :: ImageLabel
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.fromScale(0.5, 0.5)
	background.Size = UDim2.fromScale(1, 1)
	background.ScaleType = Enum.ScaleType.Stretch
	background.ZIndex = 1
	background.BackgroundColor3 = Color3.fromRGB(255, 239, 202)
	background.BackgroundTransparency = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = background
	local itemName = tooltip:FindFirstChild("ItemName") :: TextLabel
	itemName.AnchorPoint = Vector2.new(0.5, 0.5)
	itemName.Position = UDim2.fromScale(0.5, 0.5)
	itemName.Size = UDim2.new(1, -36, 1, -24)
	itemName.TextWrapped = true
	itemName.TextScaled = true
	itemName.ZIndex = 2
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize = Config.TooltipMinTextSize
	textSize.MaxTextSize = Config.TooltipMaxTextSize
	textSize.Parent = itemName
	tooltip.Parent = self.Root
	self.Tooltip = { Root = tooltip, ItemName = itemName, ActiveCard = nil }
	self.Janitor:Add(tooltip, "Destroy")
	-- Keep the authored cards and artwork; extra dining orders remain reachable on narrow screens.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GuestOrders"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(95, 49, 30)
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.Parent = container
	self.Scroll = scroll
	self.Layout = container:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	self.Layout.Parent = scroll
	self.Layout.SortOrder = Enum.SortOrder.LayoutOrder
	self.Layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Config.Layout.ContentPadding)
	padding.PaddingRight = UDim.new(0, Config.Layout.ContentPadding)
	padding.Parent = scroll
	for index = 1, Config.Slots do
		local root = container:FindFirstChild(tostring(index)) :: Frame
		root.LayoutOrder = index
		root.Parent = scroll
		local card = Card.new(root, self.Tooltip)
		self.Cards[index] = card
		self.Janitor:Add(card, "Destroy")
	end
	self.Janitor:Add(
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	DataClient:WaitForData()
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Customers" }, function(): ()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
	-- A single visual clock for all cards, including choosing dots and timestamp-derived fill.
	self.Janitor:Add(
		RunService.Heartbeat:Connect(function(deltaTime: number): ()
			self.Accumulator += deltaTime
			if self.Accumulator < Config.RefreshInterval then
				return
			end
			self.Accumulator %= Config.RefreshInterval
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		self.Root.Destroying:Connect(function(): ()
			self:Destroy()
		end),
		"Disconnect"
	)
	self:Refresh()
end

function OrderHandler.Refresh(self: OrderHandler): ()
	local orders = collectOrders()
	self.Root:SetAttribute("OrderCount", #orders)
	self.Root.Visible = #orders > 0
	while #self.Cards < #orders do
		local root = self.Template:Clone()
		root.Name = tostring(#self.Cards + 1)
		root.LayoutOrder = #self.Cards + 1
		root.Parent = self.Scroll
		local card = Card.new(root, self.Tooltip)
		table.insert(self.Cards, card)
		self.Janitor:Add(root, "Destroy")
		self.Janitor:Add(card, "Destroy")
	end
	local width = Authored.UnscaledSize(self.Scroll).X
	local slots = math.clamp((self.Root:GetAttribute("VisibleOrderSlots") :: number?) or Config.Slots, 1, Config.Slots)
	local gap = Config.Layout.CardGap
	local padding = Config.Layout.ContentPadding * 2
	local cardWidth = math.max((width - padding - gap * (slots - 1)) / slots, 1)
	self.Layout.Padding = UDim.new(0, gap)
	self.Scroll.CanvasSize = UDim2.fromOffset(math.max(0, padding + #orders * (cardWidth + gap) - gap), 0)
	local now = workspace:GetServerTimeNow()
	for index, card in self.Cards do
		card.Root.Size = UDim2.new(0, cardWidth, 1, -10)
		local order = orders[index]
		if not order then
			card:Clear()
			continue
		end
		local customer = order.Customer
		local choosing = customer.State == "Choosing"
		local recipe = if choosing then nil else Recipes:Get(customer.Orders[1])
		local names = {}
		if not choosing then
			for _, recipeId in customer.Orders do
				local dish = Recipes:Get(recipeId)
				if dish then
					names[#names + 1] = dish.name
				end
			end
		end
		-- Number dining places in purchase order: the starting table owns 1/2, the upgrade 3/4.
		-- These identify seats, so serving an earlier order never renumbers the remaining cards.
		local name = if choosing then "Picking a pastry" else table.concat(names, " + ")
		local slotOrder = Buildings.Kinds.Table.SlotOrder
		local tableIndex = Buildings.GetIndex(customer.TableId)
		local tableNumber = if slotOrder then table.find(slotOrder, tableIndex) or tableIndex else tableIndex
		local number = (tableNumber - 1) * Tables.SeatCount + (customer.SeatIndex or 1)
		local label = `#{number}`
		local remaining = if choosing or customer.TutorialProtected
			then 1
			else math.clamp((customer.PatienceEndsAt - now) / math.max(customer.Patience, 1), 0, 1)
		card:Show(
			order.CustomerId,
			recipe,
			label,
			name,
			math.ceil(remaining * Config.ProgressSteps) / Config.ProgressSteps,
			choosing,
			now
		)
	end
end

function OrderHandler.Destroy(self: OrderHandler): ()
	self.Janitor:Destroy()
end

export type OrderHandler = typeof(OrderHandler) & {
	Janitor: any,
	Cards: { Card.Card },
	Tooltip: Card.Tooltip,
	Root: Frame,
	Template: Frame,
	Scroll: ScrollingFrame,
	Layout: UIListLayout,
	Accumulator: number,
}

return OrderHandler :: OrderHandler
