--!strict
-- An authored guest card: hover/touch name, choosing dots and remaining patience over fixed art,
-- plus a generated status line over its top: what the guest needs next (Take order!, the dish to
-- cook, Serve, Eating), red while their patience runs low.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Config = require(_Shared.Configs.Orders)
local FoodPreview = require(_Shared.UI.FoodPreview)
local GuestOrders = require(_Shared.GuestOrders)
local HudLayout = require(_Shared.UI.HudLayout)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Press = require(_Shared.UI.Press)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local Theme = require(_Shared.UI.Theme)
local TextScale = require(_Shared.UI.TextScale)

--[[ Constants ]]--
local STATUS = Config.CardStatus

--[[ Types ]]--
export type Tooltip = {
	Root: Frame,
	ItemName: TextLabel,
	ActiveCard: Frame?,
}

-- One card's content, derived by OrderHandler from the replicated guest.
export type View = {
	CustomerId: string,
	Recipe: Recipes.RecipeEntry?,
	-- Seat number badge, e.g. "#3".
	Label: string,
	-- Full order name for the hover tooltip.
	Name: string,
	-- Patience left, 0-1, already stepped.
	Ratio: number,
	Need: GuestOrders.Need,
	-- One line per ordered dish.
	Status: string,
	Low: boolean,
	Now: number,
}

--[[ Tables ]]--
local Card = {}
Card.__index = Card

--[[ Private Functions ]]--
local function drawFill(clip: Frame, fill: Frame, value: number): ()
	local ratio = math.clamp(value, 0, 1)
	clip.Size = UDim2.fromScale(ratio, 1)
	-- The right edge retreats; the art keeps its full width and fixed left edge after resizing.
	fill.Size = UDim2.fromScale(if ratio > 0 then 1 / ratio else 1, 1)
	clip.Visible = ratio > 0
end

-- The cards' density: the HUD's screen density, capped like the card geometry (OrderLayout).
local function density(viewport: Vector2): number
	return TextScale.Screen(viewport, Config.Layout.MaxScale)
end

--[[ Handling ]]--
function Card.new(root: Frame, tooltip: Tooltip, onTap: (customerId: string) -> ()): Card
	local slot = root:FindFirstChild("Slot") :: Frame
	local header = root:FindFirstChild("Header") :: Frame
	header.Visible = false
	local bar = root:FindFirstChild("Bar") :: CanvasGroup
	local clip = bar:FindFirstChild("Clip") :: Frame
	local fill = clip:FindFirstChild("Fill") :: Frame
	local background = slot:FindFirstChild("Background") :: ImageLabel
	local ponder = slot:FindFirstChild("Ponder") :: TextLabel
	-- The header's place (hidden; the tooltip shows the full name) carries the status line.
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.fromScale(0.5, 0)
	status.Size = UDim2.fromScale(1, STATUS.Height)
	status.BackgroundTransparency = 1
	status.FontFace = Theme.Fonts.ExtraBold
	status.TextScaled = true
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Bottom
	status.ZIndex = STATUS.ZIndex
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = STATUS.MinTextSize
	limit.MaxTextSize = STATUS.MaxTextSize
	limit.Parent = status
	local stroke = Instance.new("UIStroke")
	stroke.Color = STATUS.StrokeColor
	stroke.Thickness = STATUS.StrokeThickness
	stroke.Parent = status
	status.Parent = root
	local self = setmetatable({
		Root = root,
		-- Centre-anchored card art: the part that punches when the order changes.
		Slot = slot,
		Background = background,
		Icon = slot:FindFirstChild("Icon") :: ImageLabel,
		Ponder = ponder,
		Status = status,
		Bar = bar,
		-- Authored looks the status states tint over and restore.
		ArtColor = background.ImageColor3,
		ArtTransparency = background.ImageTransparency,
		PonderColor = ponder.TextColor3,
		NextPulseAt = 0,
		Button = slot:FindFirstChild("Btn") :: TextButton,
		Number = slot:FindFirstChild("NumberOutside") :: TextLabel,
		Tooltip = tooltip,
		Name = "",
		Clip = clip,
		Fill = fill,
		Janitor = Janitor.new(),
		CustomerId = nil :: string?,
		RecipeId = nil :: string?,
		Hovered = false,
		Pinned = false,
		Motion = nil :: any,
	}, Card)
	self.Motion = Animate.Track(clip, "OrderRemaining", 0, function(value: number): ()
		drawFill(clip, fill, value)
	end)
	self.Janitor:Add(self.Motion, "destroy")
	self.Janitor:Add(
		Press.BindTap(self.Button, function(): ()
			self.Pinned = not self.Pinned
			if self.Pinned then
				self.Tooltip.ActiveCard = self.Root
			end
			self:RefreshHeader()
			if self.CustomerId then
				onTap(self.CustomerId)
			end
		end),
		"Destroy"
	)
	self.Janitor:Add(
		self.Button.MouseEnter:Connect(function(): ()
			self.Hovered = true
			self.Tooltip.ActiveCard = self.Root
			self:RefreshHeader()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		self.Button.MouseLeave:Connect(function(): ()
			self.Hovered = false
			self.Pinned = false
			self:RefreshHeader()
		end),
		"Disconnect"
	)
	-- Follow layout, scrolling and HUD scaling even while the pointer stays still.
	for _, property in { "AbsolutePosition", "AbsoluteSize" } do
		self.Janitor:Add(
			self.Background:GetPropertyChangedSignal(property):Connect(function(): ()
				self:RefreshHeader()
			end),
			"Disconnect"
		)
	end
	self.Janitor:Add(function(): ()
		FoodPreview.Clear(self.Icon)
	end)
	local function refreshText(): ()
		local screen = root:FindFirstAncestorWhichIsA("ScreenGui")
		local scale = if screen then density(screen.AbsoluteSize) else 1
		limit.MinTextSize = HudLayout.TextSize(STATUS.MinTextSize, scale)
		limit.MaxTextSize = HudLayout.TextSize(STATUS.MaxTextSize, scale)
	end
	self.Janitor:Add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshText), "Disconnect")
	refreshText()
	self:Clear()
	return self
end

function Card.RefreshHeader(self: Card): ()
	local tooltip = self.Tooltip
	if tooltip.ActiveCard ~= self.Root then
		return
	end
	local visible = self.CustomerId ~= nil and (self.Hovered or self.Pinned)
	tooltip.Root.Visible = visible
	tooltip.ItemName.Text = if visible then self.Name else ""
	if not visible then
		tooltip.ActiveCard = nil
		return
	end
	local parent = tooltip.Root.Parent :: GuiObject
	local parentSize = parent.AbsoluteSize
	if parentSize.X <= 0 or parentSize.Y <= 0 then
		return
	end
	-- Convert rendered card geometry to the shared tooltip parent's coordinate space.
	local topCenter = self.Background.AbsolutePosition + Vector2.new(self.Background.AbsoluteSize.X / 2, 0)
	local relative = topCenter - parent.AbsolutePosition
	local parentHud = parent.Parent
	local hud = if parentHud and parentHud:IsA("GuiObject") then parentHud else nil
	local margin = Config.TooltipMargin
	local scale = if hud then density(hud.AbsoluteSize) else 1
	local width = if hud
		then math.min(Config.TooltipWidth * scale, hud.AbsoluteSize.X - margin * 2)
		else Config.TooltipWidth
	tooltip.Root.Size = UDim2.fromOffset(width, Config.TooltipHeight * scale)
	local limit = tooltip.ItemName:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MinTextSize = HudLayout.TextSize(Config.TooltipMinTextSize, scale)
		limit.MaxTextSize = HudLayout.TextSize(Config.TooltipMaxTextSize, scale)
	end
	-- Keep the whole tooltip on the HUD near the screen edges.
	local center = relative.X
	if hud then
		local left = hud.AbsolutePosition.X - parent.AbsolutePosition.X
		center = math.clamp(center, left + width / 2 + margin, left + hud.AbsoluteSize.X - width / 2 - margin)
	end
	tooltip.Root.Position = UDim2.new(center / parentSize.X, 0, relative.Y / parentSize.Y, -Config.TooltipGap)
end

function Card.Show(self: Card, view: View): ()
	local customerId = view.CustomerId
	local recipe = view.Recipe
	local changed = self.CustomerId ~= customerId
	if changed then
		self.Hovered = false
		self.Pinned = false
	end
	local recipeId = if recipe then recipe.id else nil
	if self.RecipeId ~= recipeId then
		if recipe then
			FoodPreview.Show(self.Icon, recipe)
		else
			FoodPreview.Clear(self.Icon)
		end
	end
	self.CustomerId = customerId
	self.RecipeId = recipeId
	self.Root:SetAttribute("CustomerId", customerId)
	self.Root:SetAttribute("RecipeId", recipeId)
	self.Root.Visible = true
	self.Icon.Visible = recipe ~= nil

	local ready = view.Need == "Ready"
	local eating = view.Need == "Eating"
	self.Ponder.Visible = view.Need == "Choosing" or ready
	self.Ponder.Text = if ready then "!" else string.rep(".", math.floor(view.Now / Config.PonderInterval) % 3 + 1)
	self.Ponder.TextColor3 = if ready then STATUS.Colors.Ready else self.PonderColor
	-- A guest waiting for their order to be taken keeps calling from the HUD as well.
	if ready and view.Now >= self.NextPulseAt then
		self.NextPulseAt = view.Now + Config.ReadyPulseSeconds
		Animate.Pop(self.Slot, STATUS.ReadyPulseFrom)
	end

	self.Status.Text = view.Status
	self:Layout(string.find(view.Status, "\n", 1, true) ~= nil)
	self.Status.TextColor3 = if view.Low then STATUS.Colors.Low else STATUS.Colors[view.Need]
	self.Background.ImageColor3 = if view.Low then STATUS.LowTint else self.ArtColor
	self.Background.ImageTransparency = if eating then STATUS.EatingTransparency else self.ArtTransparency
	self.Bar.Visible = not eating

	self.Number.Text = view.Label
	local inside = self.Number:FindFirstChild("NumberInside") :: TextLabel
	inside.Text = view.Label
	self.Name = view.Name
	self:RefreshHeader()
	local ratio = view.Ratio
	self.Motion:spring(ratio)
	if changed or view.Need == "Choosing" then
		self.Motion:setPosition(ratio)
		self.Motion:setVelocity(0)
		drawFill(self.Clip, self.Fill, ratio)
	end
end

function Card.Clear(self: Card): ()
	if self.RecipeId then
		FoodPreview.Clear(self.Icon)
	end
	self.CustomerId = nil
	self.RecipeId = nil
	self.Hovered = false
	self.Pinned = false
	self.Root:SetAttribute("CustomerId", nil)
	self.Root:SetAttribute("RecipeId", nil)
	self.Root.Visible = false
	self.Status.Text = ""
	self:Layout(false)
	self.Background.ImageColor3 = self.ArtColor
	self.Background.ImageTransparency = self.ArtTransparency
	self.Ponder.TextColor3 = self.PonderColor
	self.Bar.Visible = true
	self.NextPulseAt = 0
	self:RefreshHeader()
	self.Motion:spring(0)
	self.Motion:setPosition(0)
	self.Motion:setVelocity(0)
	drawFill(self.Clip, self.Fill, 0)
end

-- Keeps the status line above the authored card number and dish art; a two-line status takes more
-- of the card and pushes the slot down.
function Card.Layout(self: Card, multiline: boolean): ()
	self.Status.Size = UDim2.fromScale(1, if multiline then STATUS.MultipleHeight else STATUS.Height)
	self.Slot.Position = UDim2.fromScale(0.5, if multiline then STATUS.MultipleSlotY else STATUS.SlotY)
	self.Slot.Size = UDim2.fromScale(1, if multiline then STATUS.MultipleSlotHeight else STATUS.SlotHeight)
end

function Card.Destroy(self: Card): ()
	self:Clear()
	self.Janitor:Destroy()
end

export type Card = typeof(setmetatable(
	{} :: {
		Root: Frame,
		Slot: Frame,
		Background: ImageLabel,
		Icon: ImageLabel,
		Ponder: TextLabel,
		Status: TextLabel,
		Bar: CanvasGroup,
		ArtColor: Color3,
		ArtTransparency: number,
		PonderColor: Color3,
		NextPulseAt: number,
		Button: TextButton,
		Number: TextLabel,
		Tooltip: Tooltip,
		Name: string,
		Clip: Frame,
		Fill: Frame,
		Janitor: any,
		Motion: any,
		CustomerId: string?,
		RecipeId: string?,
		Hovered: boolean,
		Pinned: boolean,
	},
	Card
))

return Card
