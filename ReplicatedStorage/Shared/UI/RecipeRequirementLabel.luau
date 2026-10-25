--!strict
-- A scope-owned caption on existing recipe artwork; full guidance remains available on selection.

local Config = require(script.Parent.Parent.Configs.RecipeGuidance)
local RecipeRequirements = require(script.Parent.Parent.RecipeRequirements)
local Theme = require(script.Parent.Theme)

local RecipeRequirementLabel = {}

function RecipeRequirementLabel.Create(parent: GuiObject, row: boolean): TextLabel
	local existing = parent:FindFirstChild("UpgradeRequirements")
	if existing and existing:IsA("TextLabel") then
		return existing
	end
	local style = if row then Config.Row else Config.Card
	local label = Instance.new("TextLabel")
	label.Name = "UpgradeRequirements"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = style.Position
	label.Size = style.Size
	if row then
		-- Responsive switches the caption with its row's wide and compact geometry.
		label:SetAttribute("WidePosition", Config.Row.Position)
		label:SetAttribute("WideSize", Config.Row.Size)
		label:SetAttribute("CompactPosition", Config.Row.CompactPosition)
		label:SetAttribute("CompactSize", Config.Row.CompactSize)
	end
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Bold
	label.TextColor3 = Theme.Colors.TextFace
	label.TextSize = Config.TextSize
	label.TextWrapped = true
	label.TextScaled = true
	if not row then
		label.TextYAlignment = Enum.TextYAlignment.Bottom
	end
	label.Visible = false
	label.ZIndex = 6
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = Config.MinTextSize
	constraint.MaxTextSize = Config.TextSize
	constraint.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Cocoa
	stroke.Thickness = 1
	stroke.Parent = label
	label.Parent = parent
	return label
end

function RecipeRequirementLabel.Show(label: TextLabel, ids: { string }): ()
	label.Text = RecipeRequirements.Describe(ids, Config.MaxNames)
	label.Visible = #ids > 0
end

return RecipeRequirementLabel
