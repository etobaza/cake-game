--!strict
-- Reuses authored chip art for ingredient previews; completion remains a small corner badge.
-- The owning chip controls lifetime, including the viewport's destruction subscription.

--[[ Modules ]]--
local Authored = require(script.Parent.Authored)
local FoodPreview = require(script.Parent.FoodPreview)

--[[ Tables ]]--
local IngredientChip = {}

--[[ Handling ]]--
function IngredientChip.Prepare(chip: Frame, iconTemplate: ImageLabel): ()
	local badge = chip:FindFirstChild("Icon")
	if badge and badge:IsA("ImageLabel") then
		badge.Name = "Completion"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.84, 0.18)
		badge.Size = UDim2.fromScale(0.25, 0.25)
		badge.ZIndex = 4
	end
	local icon = iconTemplate:Clone()
	icon.Image = ""
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.34)
	icon.Size = UDim2.fromScale(0.8, 0.62)
	icon.ZIndex = 3
	icon.Visible = true
	icon.Name = "Icon"
	icon.Parent = chip
	local caption = chip:FindFirstChild("Txt")
	if not caption or not caption:IsA("Frame") then
		return
	end
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.83)
	caption.Size = UDim2.fromScale(0.94, 0.28)
	for _, text in caption:GetDescendants() do
		if text:IsA("TextLabel") then
			text.TextScaled = true
			text.TextWrapped = true
		end
		if text:IsA("UITextSizeConstraint") then
			text.MinTextSize = 1
		end
	end
end

function IngredientChip.Show(chip: Frame, ingredientId: string, caption: string): ()
	chip:SetAttribute("IngredientId", ingredientId)
	Authored.SetPair(chip:FindFirstChild("Txt"), caption)
	local icon = chip:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		FoodPreview.ShowIngredient(icon, ingredientId)
	end
end

return IngredientChip
