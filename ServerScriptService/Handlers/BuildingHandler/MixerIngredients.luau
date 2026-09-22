--!strict
-- Converts the server's loaded portions into bowl visuals. FoodSurfaceView owns their lifetime.
-- No inventory writes: rejected loads, cancellation and Ready follow the existing station state.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Config = require(_Shared.Configs.MixerIngredients)
local FoodModel = require(_Shared.FoodModel)

--[[ Tables ]]--
local MixerIngredients = {}

export type Item = { Id: string, Kind: string, SeatIndex: number? }

--[[ Private Functions ]]--
local function recolor(visual: FoodModel.FoodModel, color: Color3): ()
	-- The shared atlas contains the original brown/yellow color, so tint only disposable copies.
	for _, child in visual.Model:GetDescendants() do
		if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") then
			child:Destroy()
		end
	end
	for _, entry in visual.Parts do
		local part = entry.Part
		if part:IsA("MeshPart") then
			part.TextureID = ""
		end
		part.Color = color
	end
end

--[[ Handling ]]--
function MixerIngredients.GetItems(state: any): { Item }
	local ids: { string } = {}
	for id, amount in state.Loaded or {} do
		if amount <= 0 or not Config.Entries[id] then
			continue
		end
		ids[#ids + 1] = id
	end
	-- DataHandler dictionaries do not promise iteration order; keep the visual key stable.
	table.sort(ids)
	local items: { Item } = {}
	for _, id in ids do
		for _ = 1, state.Loaded[id] do
			items[#items + 1] = { Id = id, Kind = "Ingredient" }
		end
	end
	return items
end

-- Preserve each portion's slot when an earlier-sorting ingredient arrives later.
-- Removed portions release their slots; an empty bowl discards the whole mapping.
function MixerIngredients.GetSlots(items: { Item }, previous: { [string]: number }): ({ [string]: number }, { number })
	local keys: { string } = {}
	local counts: { [string]: number } = {}
	local occupied: { [number]: boolean } = {}
	for index, item in items do
		if item.Kind ~= "Ingredient" then
			continue
		end
		counts[item.Id] = (counts[item.Id] or 0) + 1
		local key = `{item.Id}:{counts[item.Id]}`
		keys[index] = key
		local slot = previous[key]
		if slot then
			occupied[slot] = true
		end
	end
	local nextSlots: { [string]: number } = {}
	local slots: { number } = {}
	for index, key in keys do
		local slot = previous[key] or 1
		if not previous[key] then
			while occupied[slot] do
				slot += 1
			end
		end
		occupied[slot] = true
		nextSlots[key] = slot
		slots[index] = slot
	end
	return nextSlots, slots
end

function MixerIngredients.Create(id: string, slot: number, root: Instance, frame: CFrame): FoodModel.FoodModel?
	local entry = Config.Entries[id]
	if not entry then
		return nil
	end
	local visual = FoodModel.new(entry.Asset, root, Config.PortionSize)
	if not visual then
		return nil
	end
	recolor(visual, entry.Color)
	local angle = (slot - 1) * math.pi * 2 / Config.SlotCount
	local offset = CFrame.new(math.cos(angle) * Config.Radius, Config.Height, math.sin(angle) * Config.Radius)
	visual:SetCFrame(frame * offset)
	visual.Model:SetAttribute("IngredientId", id)
	visual.Model:SetAttribute("PortionIndex", slot)
	return visual
end

return MixerIngredients
