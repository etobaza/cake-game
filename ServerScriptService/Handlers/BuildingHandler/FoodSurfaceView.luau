--!strict
-- Food on one station, display shelf or dining table. Owned by the building's Janitor.
-- The authored FoodSurface is a placement point, independent of the player's interaction volume.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local BaseHandler = require(ServerScriptService.Handlers.BaseHandler)
local Config = require(_Shared.Configs.FoodPresentation)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local DiningConfig = require(_Shared.Configs.GuestDining)
local GuestsConfig = require(_Shared.Configs.Guests)
local FoodModel = require(_Shared.FoodModel)
local FoodBurn = require(_Shared.FoodBurn)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local MixerIngredients = require(script.Parent.MixerIngredients)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local TableConfig = require(_Shared.Configs.TableMenus)
local VFX = require(_Shared.Configs.VFX)

--[[ Tables ]]--
local FoodSurfaceView = {}
FoodSurfaceView.__index = FoodSurfaceView

export type FoodSurfaceView = typeof(setmetatable(
	{} :: {
		Building: any,
		Frame: CFrame,
		Frames: { CFrame },
		Root: Folder,
		Janitor: any,
		Contents: any,
		Key: string,
		IngredientSlots: { [string]: number },
		OvenFood: FoodModel.FoodModel?,
	},
	FoodSurfaceView
))

--[[ Private Functions ]]--
local function tableItems(building: any): { { Id: string, Kind: string, SeatIndex: number? } }
	local items = {}
	local root = BaseHandler:GetBase(building.Player)
	local guests = root and root:FindFirstChild(GuestsConfig.FolderName)

	for index, seat in building.State.Seats do
		if seat.Dirty then
			items[#items + 1] = { Id = TableConfig.DirtyPlateAsset, Kind = "DirtyPlate", SeatIndex = index }
			continue
		end

		local id = seat.Served[#seat.Served]
		if not id then
			continue
		end

		local guest = guests and seat.CustomerId and guests:FindFirstChild(seat.CustomerId)
		local held = guest and guest:GetAttribute(DiningConfig.HeldAttribute) == id

		items[#items + 1] = {
			Id = if held then TableConfig.CleanPlateAsset else id,
			Kind = if held then "EmptyPlate" else "Dish",
			SeatIndex = index,
		}
	end

	return items
end

local function itemsFor(building: any): { { Id: string, Kind: string, SeatIndex: number? } }
	local state = building.State
	if not state then
		return {}
	end
	if building.Kind == "Display" then
		local id = state[building.Index]
		local data = DataHandler:GetData(building.Player)
		local leftover = data and data.Session.DisplayLeftovers[building.Index]
		return if id then { { Id = id, Kind = if leftover then "Leftover" else "Dish" } } else {}
	end
	if building.Kind == "Table" then
		return tableItems(building)
	end
	if building.Kind == "Mixer" and (state.State == "Idle" or state.State == "Mixing") then
		return MixerIngredients.GetItems(state)
	end
	-- The closed chest conceals a batch while it freezes; the finished serving appears for collection.
	local freezing = building.Kind == "Freezer" and state.State ~= "Ready"
	if freezing then
		return {}
	end
	local recipe = state.RecipeId and Recipes:Get(state.RecipeId)
	if not recipe or state.State == "Idle" then
		return {}
	end
	local kind = if building.Kind == "Coffee"
		then "Dish"
		elseif state.State == "Burnt" then "Burnt"
		elseif state.State ~= "Ready" or (building.Kind == "Mixer" and recipe.cookSeconds > 0) then "Dough"
		else "Dish"
	return { { Id = recipe.id, Kind = kind } }
end

--[[ Handling ]]--
function FoodSurfaceView.new(root: Instance, building: any): FoodSurfaceView?
	local anchors = BaseHandler.Template:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(building.Id)
	local surface = anchor and anchor:FindFirstChild(Config.SurfaceAttachment)
	local transform = BaseHandler:GetTransform(building.Player)
	if not surface or not surface:IsA("Attachment") or not transform then
		return nil
	end
	local frames = { transform * surface.WorldCFrame }
	local second = if anchor then anchor:FindFirstChild(`{Config.SurfaceAttachment}2`) else nil
	if second and second:IsA("Attachment") then
		frames[2] = transform * second.WorldCFrame
	end
	local folder = Instance.new("Folder")
	folder.Name = `Food_{building.Id}`
	folder.Parent = root
	local self = setmetatable({
		Building = building,
		Frame = frames[1],
		Frames = frames,
		Root = folder,
		Janitor = Janitor.new(),
		Contents = Janitor.new(),
		Key = "",
		IngredientSlots = {},
	}, FoodSurfaceView)
	self.Janitor:Add(folder, "Destroy")
	self.Janitor:Add(self.Contents, "Destroy")
	return self
end

function FoodSurfaceView.SetFrame(self: FoodSurfaceView, frame: CFrame): ()
	if self.Frame == frame then
		return
	end
	self.Frame = frame
	self.Frames = { frame }
	self.Key = "Reposition"
end

function FoodSurfaceView.Update(self: FoodSurfaceView, _deltaTime: number, now: number): ()
	if self.OvenFood then
		self.OvenFood:SetBurn(FoodBurn.Fade(self.Building.State, now))
		if self.Building.State.State == "Burnt" then
			self.OvenFood.Model:SetAttribute("FoodKind", "Burnt")
			for _, entry in self.OvenFood.Parts do
				entry.Part:RemoveTag(VFX.Tag)
			end
		end
	end
	local items = itemsFor(self.Building)
	local keys = {}
	for _, item in items do
		-- Keep the same texture copy at the burn deadline; rebuilding would flash a fresh dish.
		local kind = if self.Building.Kind == "Oven" and item.Kind == "Burnt" then "Dish" else item.Kind
		keys[#keys + 1] = `{item.SeatIndex or 0}:{kind}:{item.Id}`
	end
	local key = table.concat(keys, "|")
	if key == self.Key then
		return
	end
	self.Key = key
	local nextSlots, slots = MixerIngredients.GetSlots(items, self.IngredientSlots)
	self.IngredientSlots = nextSlots
	self.Contents:Cleanup()
	self.OvenFood = nil
	for index, item in items do
		if item.Kind == "Ingredient" then
			local visual = MixerIngredients.Create(item.Id, slots[index], self.Root, self.Frame)
			if visual then
				self.Contents:Add(visual, "Destroy")
			end
			continue
		end
		local isTable = self.Building.Kind == "Table"
		local isOven = self.Building.Kind == "Oven"
		local size = if isTable then Config.TableFoodSize elseif isOven then Config.FoodSize else Config.SurfaceFoodSize
		local visual = if item.Kind == "DirtyPlate"
			then FoodModel.new(item.Id, self.Root, TableConfig.DirtyPlateSize)
			elseif item.Kind == "EmptyPlate" then FoodModel.new(item.Id, self.Root, TableConfig.CleanPlateSize)
			else FoodModel.ForItem(item.Id, item.Kind, self.Root, size)
		if not visual then
			continue
		end
		self.Contents:Add(visual, "Destroy")
		if isOven and (item.Kind == "Dish" or item.Kind == "Burnt") then
			self.OvenFood = visual
			visual:SetBurn(FoodBurn.Fade(self.Building.State, now))
		end
		if item.SeatIndex then
			visual.Model:SetAttribute("SeatIndex", item.SeatIndex)
		end
		local frame = self.Frames[item.SeatIndex or index] or self.Frame
		if isOven then
			frame *= Config.OvenFoodOffset
		end
		if isTable and item.Kind == "Dish" then
			local plate = FoodModel.new(TableConfig.CleanPlateAsset, self.Root, TableConfig.CleanPlateSize)
			if plate then
				self.Contents:Add(plate, "Destroy")
				plate.Model:SetAttribute("SeatIndex", item.SeatIndex)
				plate:SetCFrame(frame)
				frame *= CFrame.new(0, TableConfig.CleanPlateFoodHeight, 0)
			end
		end
		visual:SetCFrame(frame)
	end
end

function FoodSurfaceView.Destroy(self: FoodSurfaceView): ()
	self.Janitor:Destroy()
end

return FoodSurfaceView
