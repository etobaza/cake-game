--!strict
-- The Double Profit button on the day report (Configs/Offers). A clone of the report's Next Menu
-- button, recoloured and set in the Daily Profits row, shown while the evening's shift can be
-- doubled. It breathes while idle; a press buys it through the client StoreHandler like any Robux
-- product. Rescue Dish and Keep Guests wear the HUD's 2x Cash button instead (CashBoostHandler).

--[[ Services ]]--
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local Config = require(_Configs.Offers)
local DataClient = require(_Handlers.DataHandlerClient)
local Press = require(_Shared.UI.Press)
local Products = require(_Configs.Registries.Products)
local StoreHandler = require(_Handlers.StoreHandler)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local ROBUX = utf8.char(0xE002)

--[[ Tables ]]--
local OfferHandler = {
	-- The report lays its panel out first.
	dependencies = { "DataClient", "UIHandler", "ReportHandler", "StoreHandler" },
}

--[[ Private Functions ]]--
local function Recolour(button: Instance, fill: Color3, stroke: Color3): ()
	local background = button:FindFirstChild("Bg")
	if not background or not background:IsA("Frame") then
		return
	end
	background.BackgroundColor3 = fill
	local outline = background:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = stroke
	end
end

--[[ Handling ]]--
function OfferHandler.OnStart(self: OfferHandler): ()
	local spec = Config.DoubleShift.Button
	local entry = Products:Get(Config.DoubleShift.Product)
	local screen = UIHandler:GetPanel("Report")
	local panel = screen and screen:FindFirstChild("MainFrame")
	local template = panel and Authored.Resolve(panel, spec.Template)
	local row = panel and Authored.Resolve(panel, spec.Parent)
	if not entry or not row or not template or not template:IsA("GuiButton") then
		print("[OfferHandler] The report's Next Menu button or Daily Profits row is missing; no Double Profit button")
		return
	end
	self.Entry = entry

	local button = template:Clone()
	button.Name = spec.Name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = spec.Position
	button.Size = spec.Size
	button.ZIndex = template.ZIndex + 5
	button.Visible = false
	Recolour(button, spec.Color, spec.StrokeColor)
	button.Parent = row
	self.Button = button
	self:SetPrice(nil)

	Animate.Press(button)
	Press.BindTap(button, function()
		Animate.Pop(button)
		StoreHandler:Buy(Config.DoubleShift.Product)
	end)

	DataClient:WaitForData()
	DataClient:SubscribeToPath({ "DoubleShift" }, function()
		self:Refresh()
	end, "Cloud", true)
	for _, field in { "Phase", "Number" } do
		DataClient:SubscribeToPath({ "Day", field }, function()
			self:Refresh()
		end, "Session")
	end
	self:Refresh()

	RunService.PreRender:Connect(function()
		if button.Visible then
			local breath = (1 + math.sin(os.clock() * 2 * math.pi / spec.PulsePeriod)) / 2
			Animate.SetLayoutScale(button, 1 + breath * spec.PulseScale)
		end
	end)

	if entry.productId > 0 then
		task.spawn(function()
			self:FetchPrice()
		end)
	end
end

--- Shows the button only while the server would accept the press.
function OfferHandler.Refresh(self: OfferHandler): ()
	local record = DataClient:GetData({ "DoubleShift" }, "Cloud")
	local day = DataClient:GetData({ "Day" }, "Session")
	local shown = self.Entry.productId > 0 and Config.CanDoubleShift(record, day)
	if shown and not self.Button.Visible then
		Animate.Pop(self.Button)
	end
	self.Button.Visible = shown
end

--- The label carries the Marketplace price once it is known.
function OfferHandler.SetPrice(self: OfferHandler, price: number?): ()
	local text = Config.DoubleShift.Button.Text
	Authored.SetPair(self.Button:FindFirstChild("Txt"), if price then `{text}  {ROBUX}{price}` else text)
end

function OfferHandler.FetchPrice(self: OfferHandler): ()
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(self.Entry.productId, Enum.InfoType.Product)
	end)
	if not ok or not info or typeof(info.PriceInRobux) ~= "number" then
		print(`[OfferHandler] No price for {self.Entry.id}: {if ok then "not on sale" else info}`)
		return
	end
	self:SetPrice(info.PriceInRobux)
end

export type OfferHandler = typeof(OfferHandler) & {
	Entry: Products.ProductEntry,
	Button: GuiButton,
}

return OfferHandler :: OfferHandler
