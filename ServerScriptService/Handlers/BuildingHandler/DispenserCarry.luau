--!strict
-- A dispenser's authored item stays absent until its accepted pickup leaves the hands.
-- Inventory is the only state owner; every removal path and bakery teardown restores the source.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Building = require(script.Parent.Building)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local Furniture = require(script.Parent.Furniture)
local GameTypes = require(ReplicatedStorage.Shared.GameTypes)
local Janitor = require(ReplicatedStorage.Packages.janitor)

--[[ Tables ]]--
local DispenserCarry = {}
DispenserCarry.__index = DispenserCarry

export type DispenserCarry = typeof(setmetatable(
	{} :: {
		Building: Building.Building,
		Janitor: any,
		Hidden: { Furniture.Hidden }?,
	},
	DispenserCarry
))

--[[ Handling ]]--
function DispenserCarry.new(building: Building.Building): DispenserCarry
	local self = setmetatable({ Building = building, Janitor = Janitor.new() }, DispenserCarry) :: DispenserCarry
	local connection = DataHandler:SubscribeToPath(building.Player, { "Hands" }, function(): ()
		self:Refresh()
	end, "Session", true)
	if connection then
		self.Janitor:Add(connection, "Disconnect")
	end
	self:Refresh()
	return self
end

function DispenserCarry.Refresh(self: DispenserCarry): ()
	local building = self.Building
	local data = DataHandler:GetData(building.Player)
	local carried = false
	local hands: { GameTypes.ItemStack } = if data then data.Session.Hands else {}
	for _, item in hands do
		if item.Kind == "Ingredient" and item.SourceId == building.Id then
			carried = true
			break
		end
	end
	if carried == (self.Hidden ~= nil) then
		return
	end
	if not carried then
		self:Restore()
		return
	end
	local hidden: { Furniture.Hidden } = {}
	-- The dispenser is dressed onto the exact bag/cube mesh, never its tray or counter.
	Furniture.Hide(building.Part, hidden)
	self.Hidden = hidden
end

function DispenserCarry.Restore(self: DispenserCarry): ()
	if self.Hidden then
		Furniture.Restore(self.Hidden)
	end
	self.Hidden = nil
end

function DispenserCarry.Destroy(self: DispenserCarry): ()
	self.Janitor:Destroy()
	self:Restore()
end

return DispenserCarry
