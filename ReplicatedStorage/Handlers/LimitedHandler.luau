--!strict
-- Limited item showcases on this client: the plaque line, the buy prompt in the local player's own
-- bakery, the "X bought #N" toast and the idle motion (rune turning, oven floating).
--
-- The server clones the showcases and writes their stock attributes (server LimitedHandler); all the
-- text and motion here is local, so every player sees their own copy number on their own plaque.

--[[ Services ]]--
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local Bus = require(_Shared.Bus)
local Config = require(_Configs.Limited)
local DataClient = require(_Handlers.DataHandlerClient)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Products = require(_Configs.Registries.Products)
local UIHandler = require(_Handlers.UIHandler)
local UIText = require(_Configs.UIText)
local World = require(_Shared.World)

--[[ Constants ]]--
local PLAQUE_GUI = "Label"
local STOCK_LABEL = "Stock"
local RUNE_GUI = "SurfaceGui"
local RUNE_IMAGE = "Circle"

--[[ Types ]]--
type Showcase = {
	Model: Model,
	ItemId: string,
	Janitor: any,
	Prompt: ProximityPrompt?,
	Stock: TextLabel?,
	Rune: ImageLabel?,
	Oven: BasePart?,
	OvenRest: CFrame?,
}

--[[ Tables ]]--
local LimitedHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
local function itemName(itemId: string): string
	local item = Config.Items[itemId]
	local entry = item and Products:Get(item.Entry)
	return if entry and entry.meta then entry.meta.name else itemId
end

-- Presence in Cloud.Limited is ownership; the value is the copy number, 0 while it is assigned.
local function ownedSerial(itemId: string): number?
	local serial = DataClient:GetData({ "Limited", itemId }, "Cloud")
	return if typeof(serial) == "number" then serial else nil
end

local function formatCount(value: number): string
	local text = tostring(math.max(0, math.floor(value)))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Largest two units of the time left: "12d 4h", "3h 20m", "45m".
local function formatTimeLeft(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local days = total // 86400
	local hours = (total % 86400) // 3600
	local minutes = (total % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{math.max(minutes, 1)}m`
end

local function findDescendant(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

--[[ Handling ]]--
function LimitedHandler.OnInit(self: LimitedHandler): ()
	self.Showcases = {}
	self.Price = nil
end

function LimitedHandler.OnStart(self: LimitedHandler): ()
	DataClient:WaitForData()

	local folder = workspace:WaitForChild(Config.ShowcaseFolder)
	folder.ChildAdded:Connect(function(child: Instance)
		self:Bind(child)
	end)
	folder.ChildRemoved:Connect(function(child: Instance)
		self:Unbind(child)
	end)
	for _, child in folder:GetChildren() do
		self:Bind(child)
	end

	-- Ownership and the copy number both arrive through the profile.
	DataClient:SubscribeToPath({ "Limited" }, function()
		self:RefreshAll()
	end, "Cloud", true)

	-- A bakery changing hands moves the buy prompt with it.
	for _, bakery in World.WaitForBakeries():GetChildren() do
		bakery:GetAttributeChangedSignal(BaseConfig.OwnerAttribute):Connect(function()
			self:RefreshAll()
		end)
	end

	Bus.Limited.Sold.OnClientEvent:Connect(function(itemId: string, buyer: string, serial: number)
		UIHandler:Toast(`{buyer} got {itemName(itemId)} #{formatCount(serial)}!`)
	end)

	RunService.Heartbeat:Connect(function()
		self:Animate()
	end)

	-- The plaque counts the window down; once a second is plenty for minutes.
	task.spawn(function()
		while true do
			task.wait(1)
			self:RefreshAll()
		end
	end)

	task.spawn(function()
		self:LoadPrices()
	end)
end

--- Every drop is sold through the same product, so one price serves all showcases.
function LimitedHandler.LoadPrices(self: LimitedHandler): ()
	local slot = Products:Get(Config.SlotProduct)
	if not slot or slot.productId <= 0 then
		return
	end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, slot.productId, Enum.InfoType.Product)
	if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
		self.Price = info.PriceInRobux
	end
	self:RefreshAll()
end

function LimitedHandler.Bind(self: LimitedHandler, instance: Instance): ()
	local itemId = instance:GetAttribute(Config.ItemAttribute)
	if not instance:IsA("Model") or typeof(itemId) ~= "string" or not Config.Items[itemId] or self.Showcases[instance] then
		return
	end

	local janitor = Janitor.new()
	local stock = findDescendant(instance, { Config.PlaquePart, PLAQUE_GUI, STOCK_LABEL })
	local rune = findDescendant(instance, { Config.RunePart, RUNE_GUI, RUNE_IMAGE })
	local oven = instance:FindFirstChild(Config.OvenPart)

	local showcase: Showcase = {
		Model = instance,
		ItemId = itemId,
		Janitor = janitor,
		Stock = if stock and stock:IsA("TextLabel") then stock else nil,
		Rune = if rune and rune:IsA("ImageLabel") then rune else nil,
		Oven = if oven and oven:IsA("BasePart") then oven else nil,
		OvenRest = if oven and oven:IsA("BasePart") then oven.CFrame else nil,
	}
	self.Showcases[instance] = showcase

	for _, attribute in { Config.SoldAttribute, Config.StockAttribute, Config.EndsAtAttribute, Config.ActiveAttribute } do
		janitor:Add(instance:GetAttributeChangedSignal(attribute):Connect(function()
			self:Refresh(showcase)
		end), "Disconnect")
	end

	self:Refresh(showcase)
end

function LimitedHandler.Unbind(self: LimitedHandler, instance: Instance): ()
	local showcase = self.Showcases[instance]
	if not showcase then
		return
	end
	self.Showcases[instance] = nil
	showcase.Janitor:Destroy()
end

function LimitedHandler.RefreshAll(self: LimitedHandler): ()
	for _, showcase in self.Showcases do
		self:Refresh(showcase)
	end
end

--- Plaque line and prompt state for one showcase.
function LimitedHandler.Refresh(self: LimitedHandler, showcase: Showcase): ()
	local model = showcase.Model
	local stockTotal = model:GetAttribute(Config.StockAttribute)
	local sold = model:GetAttribute(Config.SoldAttribute)
	local total = if typeof(stockTotal) == "number" then stockTotal else 0
	local left = total - (if typeof(sold) == "number" then sold else 0)
	local serial = ownedSerial(showcase.ItemId)
	local owned = serial ~= nil
	local endsAt = model:GetAttribute(Config.EndsAtAttribute)
	local timeLeft = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
	local active = model:GetAttribute(Config.ActiveAttribute) == true and timeLeft > 0

	if showcase.Stock then
		showcase.Stock.Text = if serial and serial > 0
			then `YOU OWN #{formatCount(serial)}`
			elseif owned then "YOU OWN IT"
			elseif not active then "ENDED"
			elseif left <= 0 then "SOLD OUT"
			else `{formatCount(left)} LEFT - {formatTimeLeft(timeLeft)}`
	end

	local bakeryName = model:GetAttribute(Config.BakeryAttribute)
	local bakeries = World.Bakeries()
	local bakery = bakeries and typeof(bakeryName) == "string" and bakeries:FindFirstChild(bakeryName) or nil
	local isMine = bakery ~= nil and bakery:GetAttribute(BaseConfig.OwnerAttribute) == Players.LocalPlayer.UserId

	local prompt = self:EnsurePrompt(showcase)
	if prompt then
		prompt.ActionText = if self.Price then `Buy  R${self.Price}` else "Buy"
		prompt.Enabled = isMine and active and not owned and left > 0
	end
end

function LimitedHandler.EnsurePrompt(_self: LimitedHandler, showcase: Showcase): ProximityPrompt?
	if showcase.Prompt then
		return showcase.Prompt
	end

	local anchor = showcase.Model:FindFirstChild(Config.PromptAnchor)
	if not anchor or not anchor:IsA("BasePart") then
		return nil
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LimitedBuy"
	-- The client's PromptHandler draws the artist billboard for Custom prompts.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ObjectText = itemName(showcase.ItemId)
	prompt.ActionText = "Buy"
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = Config.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = anchor
	showcase.Prompt = prompt
	showcase.Janitor:Add(prompt, "Destroy")

	showcase.Janitor:Add(prompt.Triggered:Connect(function()
		if not prompt.Enabled then
			return
		end
		local reason = Bus.Limited.Buy:Fire(showcase.ItemId)
		if typeof(reason) == "string" and reason ~= "" then
			UIHandler:Toast(UIText.GetFailure(reason))
		end
	end), "Disconnect")

	return prompt
end

--- Turns the runes and floats the ovens of the showcases near the camera.
function LimitedHandler.Animate(self: LimitedHandler): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local now = os.clock()
	local focus = camera.CFrame.Position
	local rotation = (now * Config.RuneSpeed) % 360
	local lift = math.sin(now * 2 * math.pi / Config.BobPeriod) * Config.BobHeight

	for _, showcase in self.Showcases do
		local rest = showcase.OvenRest
		if not rest or (rest.Position - focus).Magnitude > Config.AnimateDistance then
			continue
		end
		if showcase.Rune then
			showcase.Rune.Rotation = rotation
		end
		if showcase.Oven then
			showcase.Oven.CFrame = rest + Vector3.new(0, lift, 0)
		end
	end
end

export type LimitedHandler = typeof(LimitedHandler) & {
	Showcases: { [Instance]: Showcase },
	Price: number?,
}

return LimitedHandler :: LimitedHandler
