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
-- (Offers.Applies: a burnt dish in an oven, a guest about to walk out), otherwise taking turns with
-- 2x Cash every SwapEvery seconds. A change slides the old face out sideways and the new one in, which
-- lands with the tap's pop and shake; a press buys the face on the button.

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

-- 0 to 1, overshooting a little past 1 before settling.
local function backOut(t: number): number
	local overshoot = 1.70158
	local u = t - 1
	return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
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
	local label = self.Label
	self.LabelPosition = if label and label:IsA("GuiObject") then label.Position else nil
	-- What a slide fades: the coin, and the label's shadow and face with their outlines.
	self.Fading = { icon }
	if label then
		local inside = label:FindFirstChild("Inside")
		local parts: { Instance } = if inside then { label, inside } else { label }
		for _, part in parts do
			table.insert(self.Fading, part)
			local outline = part:FindFirstChildOfClass("UIStroke")
			if outline then
				table.insert(self.Fading, outline)
			end
		end
	end

	local hitbox = button:FindFirstChild("Btn")
	local target = if hitbox and hitbox:IsA("GuiObject") then hitbox else button
	-- The hitbox is a bare button over the art, so the squash goes on the whole button.
	Animate.Press(target, button)
	Press.BindTap(target, function()
		self.TapAt = os.clock()
		Animate.Pop(button)
		local product = Config.Product
		if self.Shown then
			local _, offerProduct = Offers.GetHud(self.Shown)
			product = offerProduct or product
		end
		StoreHandler:Buy(product)
	end)
	self.Offer = nil
	self.Shown = nil
	self.OfferCheckAt = 0
	self.SlideAt = -math.huge
	self.SlideDirection = 1

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

	-- No tutorial gate: the face never prompts by itself, and the 2x offer it replaces is up from the
	-- first minute too.
	local session = DataClient:GetData({}, "Session")
	local now = workspace:GetServerTimeNow()
	local hud = Offers.Hud
	local onSale: { string } = {}
	local offer: string? = nil
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
	-- Nothing urgent: every other SwapEvery slot belongs to 2x Cash, the rest to the offers in turn.
	local slot = clock // hud.SwapEvery
	if not offer and #onSale > 0 and slot % 2 == 1 then
		offer = onSale[(slot // 2) % #onSale + 1]
	end
	if offer == self.Offer then
		return
	end

	-- The face itself changes halfway through the slide (SlideStep).
	self.Offer = offer
	self.SlideAt = clock
	self.SlideDirection = if offer then 1 else -1
end

--- Puts the target face on the button, landing with the same pop, coin shake and ray spin as a tap.
function CashBoostHandler.ShowFace(self: CashBoostHandler, clock: number): ()
	self.Shown = self.Offer
	local face = if self.Shown then Offers.GetHud(self.Shown) else nil
	self.Icon.Image = if face then face.Icon else Config.Button.Icon
	self.TapAt = clock
	Animate.Pop(self.Button)
end

--- The slide's sideways offset (a share of the button's width) and fade (0 opaque, 1 gone) at
--- `clock`: out along -SlideDirection, then in from +SlideDirection with an overshoot.
function CashBoostHandler.SlideStep(self: CashBoostHandler, clock: number): (number, number)
	local spec = Config.Button
	local t = clock - self.SlideAt
	if t >= spec.SlideOut and self.Shown ~= self.Offer then
		self:ShowFace(clock)
	end
	if t >= spec.SlideOut + spec.SlideIn then
		return 0, 0
	end
	local direction = self.SlideDirection
	if t < spec.SlideOut then
		local p = t / spec.SlideOut
		return -direction * p * p * spec.SlideDistance, p
	end
	local p = (t - spec.SlideOut) / spec.SlideIn
	return direction * (1 - backOut(p)) * spec.SlideDistance, math.max(0, 1 - p * 2)
end

function CashBoostHandler.SetFade(self: CashBoostHandler, fade: number): ()
	for _, part in self.Fading do
		if part:IsA("ImageLabel") then
			part.ImageTransparency = fade
		elseif part:IsA("TextLabel") then
			part.TextTransparency = fade
		elseif part:IsA("UIStroke") then
			part.Transparency = fade
		end
	end
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
	local slide, fade = self:SlideStep(clock)
	local offset = UDim2.fromScale(slide, 0)
	self:SetFade(fade)
	if self.LabelPosition and self.Label and self.Label:IsA("GuiObject") then
		self.Label.Position = self.LabelPosition + offset
	end
	local offer = self.Shown
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
		self.Icon.Position = self.IconPosition + offset
		self.IconScale.Scale = 1
	else
		self.RaysTurn = (self.RaysTurn + delta * spec.RaysSpeed * (1 + spec.TapRaysBoost * tap)) % 360
		rays.Rotation = self.RaysTurn
		local lift = hop(clock, spec.HopPeriod, spec.HopSeconds)
		self.Icon.Rotation = math.sin(clock * 2 * math.pi / spec.TiltPeriod) * spec.TiltDegrees + shake
		self.Icon.Position = self.IconPosition + offset - UDim2.fromScale(0, lift * spec.HopHeight)
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
	LabelPosition: UDim2?,
	Fading: { Instance },
	-- The contextual offer due on the button (Configs/Offers), the one drawn on it (they differ
	-- during the first half of a slide), and when to check again.
	Offer: string?,
	Shown: string?,
	OfferCheckAt: number,
	-- When the last face change started sliding, and which way (1 offer in, -1 back to 2x Cash).
	SlideAt: number,
	SlideDirection: number,
}

return CashBoostHandler :: CashBoostHandler
