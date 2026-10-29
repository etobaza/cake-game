--!strict
-- The 2x Cash button in the top-right corner of the HUD (Configs/CashBoost, placed by HudLayout).
--
-- It is a clone of the authored side Shop button stripped to its icon and label, so it keeps the
-- HUD's lettering; this handler swaps the icon and shows the time left while the boost runs. While
-- the offer is up the Store's shine rays turn behind the coin, which rocks and hops; a press squashes
-- the button and a tap pops it and shakes the coin. Pressing it goes through the client StoreHandler
-- like any Robux offer.
--
-- Rescue Dish and Keep Guests wear the button too (Configs/Offers.Hud): at once while one applies
-- (Offers.Applies: a burnt dish in an oven, a guest about to walk out), otherwise in turn for
-- RotateShow seconds every RotateEvery. The swap pops the button and shakes the coin; a press buys the
-- offer on the button.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local Config = require(_Configs.CashBoost)
local DataClient = require(_Handlers.DataHandlerClient)
local Offers = require(_Configs.Offers)
local Pages = require(_Shared.UI.Stores.Pages)
local Press = require(_Shared.UI.Press)
local Products = require(_Configs.Registries.Products)
local StoreHandler = require(_Handlers.StoreHandler)
local UIHandler = require(_Handlers.UIHandler)

--[[ Tables ]]--
local CashBoostHandler = {
	dependencies = { "DataClient", "UIHandler", "StoreHandler" },
}

--[[ Private Functions ]]--
local function formatLeft(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Zero outside a hop, rising to 1 and back over `duration` seconds after each `period`.
local function hop(clock: number, period: number, duration: number): number
	local t = clock % period
	if t > duration then
		return 0
	end
	return math.sin(t / duration * math.pi)
end

--[[ Handling ]]--
function CashBoostHandler.OnStart(self: CashBoostHandler): ()
	local spec = Config.Button
	local ok, template = pcall(UIHandler.GetHud, UIHandler, table.concat(spec.Template, ".", 2))
	if not ok or not template:IsA("GuiObject") then
		print("[CashBoostHandler] The side Shop button is missing; no 2x Cash button")
		return
	end

	local button = template:Clone()
	-- Shared/UI/HudLayout places and sizes it as soon as it joins the HUD.
	button.Name = spec.Name
	button.LayoutOrder = 0
	button.Parent = template.Parent and template.Parent.Parent
	self.Button = button

	local icon = button:FindFirstChild("Icon")
	if not icon or not icon:IsA("ImageLabel") then
		print("[CashBoostHandler] The Shop button has no Icon; no 2x Cash button")
		button:Destroy()
		return
	end
	icon.Image = spec.Icon
	self.Icon = icon
	self.IconPosition = icon.Position
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon
	self.IconScale = iconScale

	-- Only the icon and the label stay: the Shop tile behind them and its gamepad cue go.
	for _, name in { "Background", "InputCue" } do
		local child = button:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end

	-- Square, sized from the button's height and centred on the coin, drawn under the coin and the
	-- label (one ZIndex below the lowest of them).
	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.Image = spec.Rays
	rays.ImageColor3 = spec.RaysColor
	rays.ImageTransparency = spec.RaysTransparency
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = icon.Position
	rays.SizeConstraint = Enum.SizeConstraint.RelativeYY
	rays.Size = UDim2.fromScale(spec.RaysSize, spec.RaysSize)
	rays.ZIndex = icon.ZIndex - 1
	rays.Parent = button
	self.Rays = rays
	self.RaysTurn = 0
	self.TapAt = -math.huge

	self.Label = button:FindFirstChild("Shop")

	local hitbox = button:FindFirstChild("Btn")
	local target = if hitbox and hitbox:IsA("GuiObject") then hitbox else button
	-- The hitbox is a bare button over the art, so the squash goes on the whole button.
	Animate.Press(target, button)
	Press.BindTap(target, function()
		self.TapAt = os.clock()
		Animate.Pop(button)
		local product = Config.Product
		if self.Offer then
			local _, offerProduct = Offers.GetHud(self.Offer)
			product = offerProduct or product
		end
		StoreHandler:Buy(product)
	end)
	self.Offer = nil
	self.OfferCheckAt = 0

	self.LastStep = os.clock()
	DataClient:WaitForData()
	RunService.PreRender:Connect(function()
		self:Step()
	end)
end

--- The offer standing in for 2x Cash, re-read every CheckInterval: the first one in Offers.Hud.Order
--- that applies, else the rotation's turn. A change swaps the icon with a pop and the tap's shake.
function CashBoostHandler.SwapFace(self: CashBoostHandler, clock: number): ()
	if clock < self.OfferCheckAt then
		return
	end
	self.OfferCheckAt = clock + Offers.Hud.CheckInterval

	local cloud = DataClient:GetData({}, "Cloud")
	local session = DataClient:GetData({}, "Session")
	local now = workspace:GetServerTimeNow()
	local hud = Offers.Hud
	local onSale: { string } = {}
	local offer: string? = nil
	if Offers.IsPastTutorial(cloud) then
		for _, name in hud.Order do
			local _, product = Offers.GetHud(name)
			local entry = if product then Products:Get(product) else nil
			if entry and entry.productId > 0 then
				onSale[#onSale + 1] = name
				if not offer and Offers.Applies(name, session, now) then
					offer = name
				end
			end
		end
	end
	-- Nothing urgent: the offers take turns, each for RotateShow seconds of every RotateEvery.
	if not offer and #onSale > 0 and clock % hud.RotateEvery < hud.RotateShow then
		offer = onSale[(clock // hud.RotateEvery) % #onSale + 1]
	end
	if offer == self.Offer then
		return
	end

	self.Offer = offer
	local face = if offer then Offers.GetHud(offer) else nil
	self.Icon.Image = if face then face.Icon else Config.Button.Icon
	-- The same pop, coin shake and ray spin as a tap, so the swap catches the eye.
	self.TapAt = clock
	Animate.Pop(self.Button)
end

--- Animates the offer while idle and counts down while the boost runs.
function CashBoostHandler.Step(self: CashBoostHandler): ()
	local spec = Config.Button
	local button = self.Button
	button.Visible = Pages.Current:peek() == Pages.Names.None

	local clock = os.clock()
	local delta = math.min(clock - self.LastStep, 0.1)
	self.LastStep = clock
	if not button.Visible then
		return
	end

	local endsAt = DataClient:GetData({ "CashBoostEndsAt" }, "Session")
	local left = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
	self:SwapFace(clock)
	local offer = self.Offer
	-- An offer's face is idle art like the 2x offer's: rays, rocking and hopping.
	local active = left > 0 and offer == nil

	-- The tap's shake decays to nothing over TapSeconds.
	local sinceTap = clock - self.TapAt
	local tap = if sinceTap < spec.TapSeconds then 1 - sinceTap / spec.TapSeconds else 0
	local shake = if tap > 0 then math.sin(sinceTap * 40) * spec.TapDegrees * tap * tap else 0

	local rays = self.Rays
	rays.Visible = not active
	if active then
		self.Icon.Rotation = shake
		self.Icon.Position = self.IconPosition
		self.IconScale.Scale = 1
	else
		self.RaysTurn = (self.RaysTurn + delta * spec.RaysSpeed * (1 + spec.TapRaysBoost * tap)) % 360
		rays.Rotation = self.RaysTurn
		local lift = hop(clock, spec.HopPeriod, spec.HopSeconds)
		self.Icon.Rotation = math.sin(clock * 2 * math.pi / spec.TiltPeriod) * spec.TiltDegrees + shake
		self.Icon.Position = self.IconPosition - UDim2.fromScale(0, lift * spec.HopHeight)
		self.IconScale.Scale = 1 + lift * spec.HopScale
	end

	local face = if offer then Offers.GetHud(offer) else nil
	local text = if face then face.Text elseif active then formatLeft(left) else spec.IdleText
	local label = self.Label
	if label and label:IsA("TextLabel") and self.Text ~= text then
		self.Text = text
		-- The authored label is a shadow with its face as a child; both carry the text.
		label.Text = text
		Authored.SetPair(label, text)
		local inside = label:FindFirstChild("Inside")
		if inside and inside:IsA("TextLabel") then
			self.FaceColor = self.FaceColor or inside.TextColor3
			inside.TextColor3 = if active then spec.ActiveColor else self.FaceColor :: Color3
		end
	end
end

export type CashBoostHandler = typeof(CashBoostHandler) & {
	Button: GuiObject,
	Icon: ImageLabel,
	IconPosition: UDim2,
	IconScale: UIScale,
	Rays: ImageLabel,
	RaysTurn: number,
	TapAt: number,
	LastStep: number,
	Label: Instance?,
	Text: string?,
	FaceColor: Color3?,
	-- The contextual offer wearing the button (Configs/Offers), and when to check again.
	Offer: string?,
	OfferCheckAt: number,
}

return CashBoostHandler :: CashBoostHandler
