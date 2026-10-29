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
local Motion = require(_Shared.Configs.CookingMotion)
local CookingMetadata = require(script.Parent.CookingMetadata)
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

--[[ Constants ]]--
local SURFACE = Motion.Surface
local FRESH = Motion.Fresh

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
		LastState: string?,
	},
	FoodSurfaceView
))

type SurfaceItem = { Id: string, Kind: string, SeatIndex: number? }

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
	if building.Definition.Class == "DisplaySlot" then
		local id = state[building.Index]
		local data = DataHandler:GetData(building.Player)
		local leftover = data and data.Session[building.Definition.LeftoversField or "DisplayLeftovers"][building.Index]
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

-- A plate placed exactly on a table's food point clipped into the decorative cup beside it. The
-- frame steps straight away from the nearest cup until the two clear; the shift stays on the top.
-- Cups are found by name, not by a spatial query: TableMenuView hides them with CanQuery off while
-- the menu stands on the table.
local function clearOfCups(cups: { Vector3 }, frame: CFrame): CFrame
	local away: Vector3? = nil
	local distance = math.huge
	for _, cup in cups do
		local offset = (frame.Position - cup) * Vector3.new(1, 0, 1)
		if offset.Magnitude < distance then
			away, distance = offset, offset.Magnitude
		end
	end
	if not away or distance >= TableConfig.CupClearance or distance < 0.01 then
		return frame
	end
	return frame + away.Unit * (TableConfig.CupClearance - distance)
end

--[[ Handling ]]--
function FoodSurfaceView.new(root: Instance, building: any): FoodSurfaceView?
	local anchors = BaseHandler.Template:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(building.Id)
	local surface = anchor and anchor:FindFirstChild(Config.SurfaceAttachment)
	local transform = BaseHandler:GetTransform(building.Player)
	local offset = building.Definition.SurfaceOffset
	local frames: { CFrame }
	if surface and surface:IsA("Attachment") and transform then
		frames = { transform * surface.WorldCFrame }
	elseif offset then
		-- Authored parts already stand in the claimed bakery, so no template transform applies.
		frames = { building.Part.CFrame * offset }
	else
		return nil
	end
	local second = if anchor then anchor:FindFirstChild(`{Config.SurfaceAttachment}2`) else nil
	if second and second:IsA("Attachment") and transform then
		frames[2] = transform * second.WorldCFrame
	end
	local bakery = if building.Kind == "Table" then BaseHandler:GetBase(building.Player) else nil
	if bakery then
		local cups: { Vector3 } = {}
		for _, descendant in bakery:GetDescendants() do
			if descendant:IsA("Model") and descendant.Name == TableConfig.CupModelName then
				local position = descendant:GetPivot().Position
				local fromTable = position - building.Part.Position
				if Vector3.new(fromTable.X, 0, fromTable.Z).Magnitude <= TableConfig.Radius and math.abs(fromTable.Y) <= 4 then
					table.insert(cups, position)
				end
			end
		end
		for index, frame in frames do
			frames[index] = clearOfCups(cups, frame)
		end
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
		LastState = building.State and building.State.State,
	}, FoodSurfaceView)
	self.Janitor:Add(folder, "Destroy")
	self.Janitor:Add(self.Contents, "Destroy")
	if building.Kind == "Mixer" then
		folder:SetAttribute(SURFACE.StationKind, building.Kind)
		folder:SetAttribute(SURFACE.SurfaceFrame, self.Frame)
		folder:AddTag(Motion.SurfaceTag)
	end
	return self
end

function FoodSurfaceView.SetFrame(self: FoodSurfaceView, frame: CFrame): ()
	if self.Frame == frame then
		return
	end
	self.Frame = frame
	self.Root:SetAttribute(SURFACE.SurfaceFrame, frame)
	self.Frames = { frame }
	self.Key = "Reposition"
end

-- Mixer surfaces replicate the authoritative mixing window and batter color for the client swirl.
-- The window survives Ready so the local dough can hand over to the server result.
local function applyMixerMetadata(self: FoodSurfaceView, state: any): ()
	CookingMetadata.Apply(self.Root, state, self.Building.Player)
	self.Root:SetAttribute(SURFACE.RecipeId, state.RecipeId)
	local recipe = state.RecipeId and Recipes:Get(state.RecipeId)
	self.Root:SetAttribute(SURFACE.BatterColor, if recipe then Recipes:GetDoughColor(recipe) else nil)
	if state.State == "Mixing" then
		self.Root:SetAttribute(SURFACE.MixStartedAt, state.PhaseStartedAt)
		self.Root:SetAttribute(SURFACE.MixReadyAt, state.ReadyAt)
	elseif state.State ~= "Ready" then
		self.Root:SetAttribute(SURFACE.MixStartedAt, 0)
		self.Root:SetAttribute(SURFACE.MixReadyAt, 0)
	end
end

local function applyOvenBurn(self: FoodSurfaceView, now: number): ()
	local ovenFood = self.OvenFood
	if not ovenFood then
		return
	end
	ovenFood:SetBurn(FoodBurn.Fade(self.Building.State, now))
	if self.Building.State.State ~= "Burnt" then
		-- A rescued dish (OfferHandler) is Ready again on the burnt copy: rebuild it fresh, steam and all.
		-- An empty key never matches a dish's, so Update rebuilds the contents.
		if ovenFood.Model:GetAttribute(FRESH.FoodKind) == "Burnt" then
			self.Key = ""
		end
		return
	end
	ovenFood.Model:RemoveTag(Motion.FreshTag)
	ovenFood.Model:SetAttribute(FRESH.FoodKind, "Burnt")
	for _, entry in ovenFood.Parts do
		entry.Part:RemoveTag(VFX.Tag)
	end
end

local function contentKey(building: any, items: { SurfaceItem }): string
	local keys = {}
	for _, item in items do
		-- Keep the same texture copy at the burn deadline; rebuilding would flash a fresh dish.
		local kind = if building.Kind == "Oven" and item.Kind == "Burnt" then "Dish" else item.Kind
		keys[#keys + 1] = `{item.SeatIndex or 0}:{kind}:{item.Id}`
	end
	return table.concat(keys, "|")
end

-- A served dish stands on a clean plate; returns the frame the dish sits at above the plate.
local function placePlate(self: FoodSurfaceView, item: SurfaceItem, frame: CFrame): CFrame
	local plate = FoodModel.new(TableConfig.CleanPlateAsset, self.Root, TableConfig.CleanPlateSize)
	if not plate then
		return frame
	end
	self.Contents:Add(plate, "Destroy")
	plate.Model:SetAttribute("SeatIndex", item.SeatIndex)
	plate:SetCFrame(frame)
	return frame * CFrame.new(0, TableConfig.CleanPlateFoodHeight, 0)
end

local function buildItemVisual(
	self: FoodSurfaceView,
	item: SurfaceItem,
	index: number,
	slots: { number },
	fresh: boolean,
	now: number
): ()
	if item.Kind == "Ingredient" then
		local ingredient = MixerIngredients.Create(item.Id, slots[index], self.Root, self.Frame)
		if ingredient then
			self.Contents:Add(ingredient, "Destroy")
		end
		return
	end
	local isTable = self.Building.Kind == "Table"
	local isOven = self.Building.Kind == "Oven"
	local size = if isTable then Config.TableFoodSize elseif isOven then Config.FoodSize else Config.SurfaceFoodSize
	local visual = if item.Kind == "DirtyPlate"
		then FoodModel.new(item.Id, self.Root, TableConfig.DirtyPlateSize)
		elseif item.Kind == "EmptyPlate" then FoodModel.new(item.Id, self.Root, TableConfig.CleanPlateSize)
		else FoodModel.ForItem(item.Id, item.Kind, self.Root, size)
	if not visual then
		return
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
		frame = placePlate(self, item, frame)
	end
	visual:SetCFrame(frame)
	if fresh and (item.Kind == "Dish" or item.Kind == "Dough") then
		visual.Model:SetAttribute(FRESH.CompletedAt, now)
		visual.Model:SetAttribute(FRESH.CompletionFrame, frame)
		visual.Model:AddTag(Motion.FreshTag)
	end
end

function FoodSurfaceView.Update(self: FoodSurfaceView, _deltaTime: number, now: number): ()
	local state = self.Building.State
	local stationState = state and state.State
	local fresh = stationState == "Ready" and (self.LastState == "Mixing" or self.LastState == "Cooking")
	self.LastState = stationState
	if self.Building.Kind == "Mixer" and state then
		applyMixerMetadata(self, state)
	end
	applyOvenBurn(self, now)

	local items = itemsFor(self.Building)
	local key = contentKey(self.Building, items)
	if key == self.Key and not fresh then
		return
	end
	self.Key = key
	local nextSlots, slots = MixerIngredients.GetSlots(items, self.IngredientSlots)
	self.IngredientSlots = nextSlots
	self.Contents:Cleanup()
	self.OvenFood = nil
	for index, item in items do
		buildItemVisual(self, item, index, slots, fresh, now)
	end
end

function FoodSurfaceView.Destroy(self: FoodSurfaceView): ()
	self.Janitor:Destroy()
end

return FoodSurfaceView
