--!strict
-- The 2x Cash button in the top-right corner of the HUD (Configs/CashBoost, placed by HudLayout).
--
-- It is a clone of the authored side Shop button stripped to its icon and label, so it keeps the
-- HUD's lettering; this handler swaps the icon, pulses it gently and shows the time left while the
-- boost runs. Pressing it goes through the client StoreHandler like any Robux offer.

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
local Pages = require(_Shared.UI.Stores.Pages)
local Press = require(_Shared.UI.Press)
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
	if icon and icon:IsA("ImageLabel") then
		icon.Image = spec.Icon
	end

	-- Only the icon and the label stay: the Shop tile behind them and its gamepad cue go.
	for _, name in { "Background", "InputCue" } do
		local child = button:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end

	local scale = Instance.new("UIScale")
	scale.Parent = button
	self.Scale = scale

	self.Label = button:FindFirstChild("Shop")

	local hitbox = button:FindFirstChild("Btn")
	local target = if hitbox and hitbox:IsA("GuiObject") then hitbox else button
	Animate.Press(target)
	Press.BindTap(target, function()
		StoreHandler:Buy(Config.Product)
	end)

	DataClient:WaitForData()
	RunService.PreRender:Connect(function()
		self:Step()
	end)
end

--- Pulses while idle and counts down while the boost runs.
function CashBoostHandler.Step(self: CashBoostHandler): ()
	local spec = Config.Button
	local button = self.Button
	button.Visible = Pages.Current:peek() == Pages.Names.None

	if not button.Visible then
		return
	end

	local clock = os.clock()

	local endsAt = DataClient:GetData({ "CashBoostEndsAt" }, "Session")
	local left = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
	local active = left > 0

	self.Scale.Scale = if active then 1 else 1 + math.sin(clock * 2 * math.pi / spec.PulsePeriod) * spec.PulseScale

	local text = if active then formatLeft(left) else spec.IdleText
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
	Scale: UIScale,
	Label: Instance?,
	Text: string?,
	FaceColor: Color3?,
}

return CashBoostHandler :: CashBoostHandler
