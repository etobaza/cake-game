--!strict
-- Resolves configured ingredient and fuel templates; FoodModel owns the disposable normalized geometry.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Appearance = require(script.Parent.CarriedAppearance)
local Config = require(script.Parent.Configs.CarryPresentation)
local FoodModel = require(script.Parent.FoodModel)

--[[ Private Variables ]]--
local Warned: { [string]: boolean } = {}

--[[ Tables ]]--
local CarryModel = {}

--[[ Handling ]]--
function CarryModel.new(item: Appearance.Item, parent: Instance): FoodModel.FoodModel?
	if not item.Id then
		return nil
	end
	local entries = Config.Items[item.Kind]
	local entry = entries and entries[item.Id]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source: Instance? = assets and assets:FindFirstChild("Models")
	for _, name in ((entry and entry.Asset) or {}) :: { string } do
		source = source and source:FindFirstChild(name)
	end
	if not entry or not source then
		local key = `{item.Kind}/{item.Id}`
		if not Warned[key] then
			warn(`[CarryModel] No authored carry model for {key}`)
			Warned[key] = true
		end
		return nil
	end
	local visual = FoodModel.FromSource(source, parent, entry.MaxSize, false, entry.Rotation)
	if visual then
		visual.Model:SetAttribute("ItemKind", item.Kind)
		visual.Model:SetAttribute("ItemId", item.Id)
	end
	return visual
end

return CarryModel
