--!strict
-- An authored guest card: hover/touch name, choosing dots and remaining patience over fixed art.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Config = require(_Shared.Configs.Orders)
local FoodPreview = require(_Shared.UI.FoodPreview)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Press = require(_Shared.UI.Press)
local Recipes = require(_Shared.Configs.Registries.Recipes)

--[[ Types ]]--
export type Tooltip = {
	Root: Frame,
	ItemName: TextLabel,
	ActiveCard: Frame?,
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

--[[ Handling ]]--
function Card.new(root: Frame, tooltip: Tooltip): Card
	local slot = root:FindFirstChild("Slot") :: Frame
	local header = root:FindFirstChild("Header") :: Frame
	header.Visible = false
	local bar = root:FindFirstChild("Bar") :: CanvasGroup
	local clip = bar:FindFirstChild("Clip") :: Frame
	local fill = clip:FindFirstChild("Fill") :: Frame
	local self = setmetatable({
		Root = root,
		Background = slot:FindFirstChild("Background") :: ImageLabel,
		Icon = slot:FindFirstChild("Icon") :: ImageLabel,
		Ponder = slot:FindFirstChild("Ponder") :: TextLabel,
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
	tooltip.Root.Position = UDim2.new(relative.X / parentSize.X, 0, relative.Y / parentSize.Y, -Config.TooltipGap)
end

function Card.Show(
	self: Card,
	customerId: string,
	recipe: Recipes.RecipeEntry?,
	label: string,
	name: string,
	ratio: number,
	choosing: boolean,
	now: number
): ()
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
	self.Ponder.Visible = choosing
	self.Ponder.Text = string.rep(".", math.floor(now / Config.PonderInterval) % 3 + 1)
	self.Number.Text = label
	local inside = self.Number:FindFirstChild("NumberInside") :: TextLabel
	inside.Text = label
	self.Name = name
	self:RefreshHeader()
	self.Motion:spring(ratio)
	if changed or choosing then
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
	self:RefreshHeader()
	self.Motion:spring(0)
	self.Motion:setPosition(0)
	self.Motion:setVelocity(0)
	drawFill(self.Clip, self.Fill, 0)
end

function Card.Destroy(self: Card): ()
	self:Clear()
	self.Janitor:Destroy()
end

export type Card = typeof(setmetatable(
	{} :: {
		Root: Frame,
		Background: ImageLabel,
		Icon: ImageLabel,
		Ponder: TextLabel,
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
