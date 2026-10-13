--!strict
-- Extends the authored friend-boost row. The existing Currency group owns reveal and page motion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Animate = require(Shared.UI.Animate)
local HudLayout = require(Shared.UI.HudLayout)
local Invite = require(Shared.Configs.Friends).Invite
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Theme = require(Shared.UI.Theme)

local Control = {}

function Control.Bind(currency: GuiObject, hud: GuiObject): (TextButton, any)
	local owner = Janitor.new()
	local label = currency:FindFirstChild("FriendBoost")
	if not label or not label:IsA("TextLabel") then
		error("[InviteHandler] Currency.FriendBoost must be an authored TextLabel")
	end
	local boost = label
	local original = {
		Size = boost.Size,
		Position = boost.Position,
		AnchorPoint = boost.AnchorPoint,
		Visible = boost.Visible,
	}
	local constraints: { UITextSizeConstraint } = {}
	local texts: { TextLabel } = { boost }
	local inside = boost:FindFirstChild("Inside")
	if inside and inside:IsA("TextLabel") then
		texts[#texts + 1] = inside
	end
	for _, text in texts do
		local existing = text:FindFirstChildOfClass("UITextSizeConstraint")
		local constraint = existing or Instance.new("UITextSizeConstraint")
		if existing then
			local minimum, maximum = constraint.MinTextSize, constraint.MaxTextSize
			owner:Add(function(): ()
				constraint.MinTextSize = minimum
				constraint.MaxTextSize = maximum
			end)
		else
			constraint.Parent = text
			owner:Add(constraint, "Destroy")
		end
		constraints[#constraints + 1] = constraint
	end
	owner:Add(function(): ()
		boost.Size = original.Size
		boost.Position = original.Position
		boost.AnchorPoint = original.AnchorPoint
		boost.Visible = original.Visible
	end)

	local button = Instance.new("TextButton")
	button.Name = "Invite"
	button.Text = "Invite friends"
	button.TextTransparency = 1
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Selectable = true
	button.SelectionOrder = 20
	button.ZIndex = boost.ZIndex + 1
	for _, text in texts do
		button.ZIndex = math.max(button.ZIndex, text.ZIndex + 1)
	end
	-- One transparent hitbox covers the inline icon and both authored text layers.
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Image = Invite.Icon
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Active = false
	icon.ZIndex = button.ZIndex + 1
	icon.Parent = button
	button.Parent = currency
	owner:Add(button, "Destroy")
	local resetPress = Animate.Press(button, icon, owner)
	owner:Add(
		button:GetPropertyChangedSignal("Visible"):Connect(function(): ()
			boost.Visible = original.Visible and button.Visible
			if not button.Visible then
				resetPress()
			end
		end),
		"Disconnect"
	)
	owner:Add(
		button:GetAttributeChangedSignal("InviteState"):Connect(function(): ()
			local busy = button:GetAttribute("InviteState") ~= "Idle"
			icon.ImageTransparency = if busy then 0.3 else 0
			if busy then
				resetPress()
			end
		end),
		"Disconnect"
	)

	local function layout(): ()
		-- HudLayout draws Currency at the HUD density, so its width against the desktop plate is that
		-- density. Below desktop size the icon shrinks with it; above, it keeps its pixel size.
		local scale = currency.Size.X.Offset / Invite.DesktopCurrencyWidth
		local iconScale = math.min(scale, 1)
		local width = currency.Size.X.Offset
		local height = currency.Size.Y.Offset
		local textLeft = width * original.Position.X.Scale + original.Position.X.Offset
		local top = height * original.Position.Y.Scale + original.Position.Y.Offset
		local padding = Invite.HitPadding * scale
		local iconSize = Invite.IconSize * iconScale
		local inlineWidth = iconSize + Invite.IconGap * iconScale
		local currencyLeft = currency.AbsolutePosition.X - hud.AbsolutePosition.X
		local home = currency:GetAttribute("HomePosition")
		if typeof(home) == "UDim2" then
			currencyLeft = hud.AbsoluteSize.X * home.X.Scale + home.X.Offset - width * currency.AnchorPoint.X
		end
		-- Keep the authored text's left edge when room exists; narrow HUDs reserve space for the icon.
		local left = math.max(textLeft - inlineWidth, Invite.EdgePadding - currencyLeft + padding)
		local available = hud.AbsoluteSize.X - currencyLeft - left - Invite.EdgePadding + padding
		local rowWidth = math.min(Invite.TextWidth * scale + inlineWidth + padding * 2, available)
		local rowHeight = Invite.RowHeight * scale
		-- The hitbox stays a usable touch target around the row's centre line on small screens.
		local hitHeight = math.max(rowHeight, Theme.ScreenScale.MinTouchPixels)
		boost.AnchorPoint = Vector2.new(0, 0.5)
		boost.Position = UDim2.fromOffset(left + inlineWidth, top + rowHeight / 2)
		boost.Size = UDim2.fromOffset(math.max(1, rowWidth - inlineWidth - padding * 2), Invite.TextHeight * scale)
		button.Position = UDim2.fromOffset(left - padding, top + (rowHeight - hitHeight) / 2)
		button.Size = UDim2.fromOffset(rowWidth, hitHeight)
		icon.Position = UDim2.new(0, padding, 0.5, 0)
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
		for _, constraint in constraints do
			constraint.MinTextSize = HudLayout.TextSize(Invite.MinTextSize, scale)
			constraint.MaxTextSize = HudLayout.TextSize(Invite.TextSize, scale)
		end
	end
	owner:Add(currency:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout), "Disconnect")
	owner:Add(currency:GetAttributeChangedSignal("HomePosition"):Connect(layout), "Disconnect")
	owner:Add(hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout), "Disconnect")
	owner:LinkToInstance(currency)
	layout()
	return button, owner
end

return Control
