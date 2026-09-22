--!strict
-- Menu books follow their dining place; decorative cups stay hidden while a menu is shown.
-- Static dirty-plate dressing is hidden while owned;
-- FoodSurfaceView shows dirt from seat state, and teardown restores the authored decorations.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local BaseHandler = require(ServerScriptService.Handlers.BaseHandler)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Config = require(ReplicatedStorage.Shared.Configs.TableMenus)
local FoodConfig = require(ReplicatedStorage.Shared.Configs.FoodPresentation)
local Furniture = require(script.Parent.Furniture)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local TableMenuView = {}
TableMenuView.__index = TableMenuView

type Place =
	{ Menus: { Model }, Cups: { Model }, Position: Vector3, Hidden: boolean, CupsHidden: boolean, Janitor: any }

export type TableMenuView = typeof(setmetatable(
	{} :: {
		Building: any,
		Places: { Place },
		Janitor: any,
	},
	TableMenuView
))

--[[ Private Functions ]]--
local function nearestPlace(places: { Place }, position: Vector3): Place?
	local best: Place? = nil
	local distance = math.huge
	for _, place in places do
		local gap = (place.Position - position).Magnitude
		if gap < distance then
			best, distance = place, gap
		end
	end
	return best
end

local function setHidden(place: Place, hidden: boolean): ()
	if hidden == place.Hidden then
		return
	end
	place.Hidden = hidden
	if not hidden then
		place.Janitor:Remove("Menus")
		return
	end
	local originals: { Furniture.Hidden } = {}
	for _, menu in place.Menus do
		Furniture.Hide(menu, originals)
	end
	place.Janitor:Add(function()
		Furniture.Restore(originals)
	end, true, "Menus")
end

local function setCupsHidden(place: Place, hidden: boolean): ()
	if hidden == place.CupsHidden then
		return
	end
	place.CupsHidden = hidden
	if not hidden then
		place.Janitor:Remove("Cups")
		return
	end
	local originals: { Furniture.Hidden } = {}
	for _, cup in place.Cups do
		Furniture.Hide(cup, originals)
	end
	place.Janitor:Add(function()
		Furniture.Restore(originals)
	end, true, "Cups")
end

--[[ Handling ]]--
function TableMenuView.new(root: Instance, building: any): TableMenuView?
	local path = Config.Paths[building.Index]
	local holder = path and Buildings.ResolvePath(root, path)
	local anchors = BaseHandler.Template:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(building.Id)
	local transform = BaseHandler:GetTransform(building.Player)
	if not holder or not anchor or not transform then
		return nil
	end

	local self =
		setmetatable({ Building = building, Places = {}, Janitor = Janitor.new() }, TableMenuView) :: TableMenuView
	for index = 1, Config.SeatCount do
		local name = if index == 1 then FoodConfig.SurfaceAttachment else `{FoodConfig.SurfaceAttachment}{index}`
		local surface = anchor:FindFirstChild(name)
		if not surface or not surface:IsA("Attachment") then
			self:Destroy()
			return nil
		end
		local place: Place = {
			Menus = {},
			Cups = {},
			Position = transform * surface.WorldPosition,
			Hidden = false,
			CupsHidden = false,
			Janitor = Janitor.new(),
		}
		self.Places[index] = place
		self.Janitor:Add(place.Janitor, "Destroy")
	end

	local originals: { Furniture.Hidden } = {}
	for _, child in holder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local part = child:FindFirstChildWhichIsA("BasePart", true)
		if not part then
			continue
		end
		local offset = part.Position - building.Part.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.Radius then
			continue
		end
		if child.Name == Config.DirtyPlateName then
			Furniture.Hide(child, originals)
		elseif child.Name == Config.ModelName then
			local place = nearestPlace(self.Places, part.Position)
			if place then
				place.Menus[#place.Menus + 1] = child
			end
		elseif child.Name == Config.CupModelName then
			local place = nearestPlace(self.Places, part.Position)
			if place then
				place.Cups[#place.Cups + 1] = child
			end
		end
	end
	self.Janitor:Add(function()
		Furniture.Restore(originals)
	end, true)
	self:Update(0, 0)
	return self
end

function TableMenuView.Update(self: TableMenuView, _deltaTime: number, _now: number): ()
	local state = self.Building.State
	if not state then
		return
	end
	for index, place in self.Places do
		local seat = state.Seats[index]
		setHidden(place, seat ~= nil and seat.MenuHidden == true)
		-- Only authored decoration is affected. FoodSurfaceView owns any actually served coffee.
		setCupsHidden(place, not place.Hidden)
	end
end

function TableMenuView.Destroy(self: TableMenuView): ()
	self.Janitor:Destroy()
end

return TableMenuView
