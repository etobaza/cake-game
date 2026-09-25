--!strict
-- The Store screen, and the two Robux buttons that live on the reward screens.
--
-- Drives the Store screen authored in StarterGui: five currency tiles, two gamepass rows and one
-- featured row, each already drawn with a price plate and a Buy button. Nothing is built here; the
-- rows are filled from the product registry and the order comes from Configs/Store.
--
-- A product whose id is still 0 has not been created on the Dashboard yet. Its row shows what it
-- would be and the press says so, instead of prompting Roblox for a product that does not exist.

--[[ Services ]]--
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local CardGrid = require(_Shared.UI.CardGrid)
local Authored = require(_Shared.UI.Authored)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local Press = require(_Shared.UI.Press)
local Products = require(_Configs.Registries.Products)
local StoreConfig = require(_Configs.Store)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local SCREEN_NAME = "Store"
local CURRENCY_PATH = { "MainFrame", "Container", "Content", "Currency", "Content" }
local GAMEPASS_PATH = { "MainFrame", "Container", "Content", "Gamepasses" }
local FEATURED_PATH = { "MainFrame", "Container", "Content" }
local OWNED_PATH = { "MainFrame", "Container", "Content", "Gamepasses", "Header", "Capacity" }
-- Where the reward screens keep their Robux buttons.
local DAILY_SKIP = { screen = "DailyRewards", path = { "MainFrame", "Buttons" }, names = { "Skip1", "SkipAll" } }
local PLAYTIME_SKIP = { screen = "Playtime", path = { "MainFrame", "Bottom" }, names = { "Skip" } }

-- What the price plate says once the pass is owned.
local OWNED_LABEL = "Owned"

--[[ Tables ]]--
local StoreHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
-- Rows were all drawn under the same name, so they are taken in the order the list layout shows them.
local function RowsUnder(parent: Instance, prefix: string): { Frame }
	local rows = {}

	for _, child in parent:GetChildren() do
		if child:IsA("Frame") and string.sub(child.Name, 1, #prefix) == prefix then
			rows[#rows + 1] = child
		end
	end

	return rows
end

local function Owns(entryId: string): boolean
	for _, owned in DataClient:GetData({ "Passes" }, "Cloud") or {} do
		if owned == entryId then
			return true
		end
	end

	return false
end

--[[ Handling ]]--
function StoreHandler.OnStart(self: StoreHandler): ()
	local screen = UIHandler:GetPanel(SCREEN_NAME)
	if not screen then
		print(`[StoreHandler] '{SCREEN_NAME}' is missing; the store is disabled`)
		return
	end

	self.Screen = screen
	self.Rows = {}
	local currency = Authored.Resolve(screen, CURRENCY_PATH)
	if currency and currency:IsA("GuiObject") then
		CardGrid.Bind(currency)
	end

	self:BindSection(Authored.Resolve(screen, CURRENCY_PATH), "Item", StoreConfig.Currency)
	self:BindSection(Authored.Resolve(screen, GAMEPASS_PATH), "Item", StoreConfig.Gamepasses)
	self:BindSection(Authored.Resolve(screen, FEATURED_PATH), "Item", StoreConfig.Featured)
	self:BindSkips()

	DataClient:WaitForData()
	self:Refresh()

	DataClient:SubscribeToPath({ "Passes" }, function()
		self:Refresh()
	end, "Cloud", true)

	-- Robux prices come from the Marketplace, one web call each, so they are fetched once in the
	-- background rather than every time the screen opens.
	task.spawn(function()
		self:FetchPrices()
	end)
end

--- Fills one drawn section with as many products as it was given, and hides the tiles left over.
function StoreHandler.BindSection(self: StoreHandler, parent: Instance?, prefix: string, entryIds: { string }): ()
	if not parent then
		print(`[StoreHandler] '{SCREEN_NAME}' is missing a section`)
		return
	end

	local rows = RowsUnder(parent, prefix)

	for index, row in rows do
		local entryId = entryIds[index]
		local entry = entryId and Products:Get(entryId)

		if not entry or not entry.meta then
			row.Visible = false
			continue
		end

		row.Visible = true
		self.Rows[#self.Rows + 1] = { Row = row, EntryId = entryId :: string }

		local meta = entry.meta
		Authored.SetPair(row:FindFirstChild("Value"), meta.value or "")
		Authored.SetPair(row:FindFirstChild("Name"), meta.name)
		Authored.SetPair(row:FindFirstChild("Cake"), meta.name)

		local item = row:FindFirstChild("Item")
		if item and item:IsA("TextLabel") then
			item.Text = meta.name
		end

		local contains = row:FindFirstChild("Contains")
		if contains and contains:IsA("TextLabel") and meta.blurb then
			contains.Text = meta.blurb
		end

		local buy = row:FindFirstChild("Buy")
		if buy and buy:IsA("GuiObject") then
			Animate.Press(buy)
			Press.BindTap(buy, function()
				self:Buy(entryId :: string)
			end)
		end
	end
end

--- The Skip plates on the reward screens are the same kind of purchase, so they are bound the same way.
function StoreHandler.BindSkips(self: StoreHandler): ()
	for _, spec in { DAILY_SKIP, PLAYTIME_SKIP } do
		local screen = UIHandler:GetPanel(spec.screen)
		local holder = screen and Authored.Resolve(screen, spec.path)
		if not holder then
			continue
		end

		local entryId = if spec.screen == "DailyRewards" then StoreConfig.Skips.Daily else StoreConfig.Skips.Playtime

		for _, name in spec.names do
			local plate = holder:FindFirstChild(name)
			if plate and plate:IsA("GuiObject") then
				Animate.Press(plate)
				Press.BindTap(plate, function()
					self:Buy(entryId)
				end)
			end
		end
	end
end

--- Asks the server to open the Roblox prompt. A product with no id yet never gets that far.
function StoreHandler.Buy(_self: StoreHandler, entryId: string): ()
	local entry = Products:Get(entryId)
	if not entry then
		return
	end

	if entry.productId <= 0 then
		UIHandler:Toast(`{if entry.meta then entry.meta.name else entryId} is not on sale yet`)
		return
	end

	if entry.productType ~= "devproduct" and Owns(entryId) then
		UIHandler:Toast("You already own that")
		return
	end

	Bus.Purchase.RequestPurchase:Fire(entry.productId)
end

--- Owned passes read as owned, and the header counts them.
function StoreHandler.Refresh(self: StoreHandler): ()
	local owned = 0

	for _, row in self.Rows do
		local entry = Products:Get(row.EntryId)
		if not entry or entry.productType == "devproduct" then
			continue
		end

		local has = Owns(row.EntryId)
		if has then
			owned += 1
		end

		-- The drawn price is left alone until the Marketplace answers with the real one: a row that
		-- says nothing reads worse than a row that says the placeholder.
		local buy = row.Row:FindFirstChild("Buy")
		local price = buy and Authored.Resolve(buy, { "Price" })
		local label = if has then OWNED_LABEL else row.Price

		if price and label then
			Authored.SetPair(price, label)
		end
	end

	Authored.SetPair(Authored.Resolve(self.Screen, OWNED_PATH), `{owned}/{StoreConfig.OwnedTotal} Owned`)
end

--- Robux prices, read once. A missing id or a failed call leaves the drawn placeholder alone.
function StoreHandler.FetchPrices(self: StoreHandler): ()
	for _, row in self.Rows do
		local entry = Products:Get(row.EntryId)
		if not entry or entry.productId <= 0 then
			continue
		end

		local infoType = if entry.productType == "gamepass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(entry.productId, infoType)
		end)

		if ok and info and info.PriceInRobux then
			row.Price = tostring(info.PriceInRobux)
		end
	end

	self:Refresh()
end

export type StoreRow = {
	Row: Frame,
	EntryId: string,
	Price: string?,
}

export type StoreHandler = typeof(StoreHandler) & {
	Screen: ScreenGui,
	Rows: { StoreRow },
}

return StoreHandler :: StoreHandler
