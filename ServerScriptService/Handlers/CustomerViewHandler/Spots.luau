--!strict
-- Where a guest belongs in the room: the chair at their table, a place at the display, or the queue
-- by the door. Pure geometry over the buildings that already stand, no state of its own.
-- Offsets are measured in the building's own space, so they survive the room being re-laid out.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local BuildingHandler = require(_Handlers.BuildingHandler)
local BuildingsConfig = require(_Configs.Buildings)
local GuestsConfig = require(_Configs.Guests)
local FoodPresentation = require(_Configs.FoodPresentation)
local TableConfig = require(_Configs.TableMenus)
local UpgradeHandler = require(_Handlers.UpgradeHandler)

--[[ Constants ]]--
local DOOR_ID = "door"
-- Building kind the display guests walk up to, and the customer kind that does it.
local DISPLAY_KIND = "Display"
local DISPLAY_GUEST = "Display"

--[[ Tables ]]--
local Spots = {}

export type Spot = {
	Target: Vector3,
	Approach: Vector3?,
	LookAt: Vector3?,
	Seat: Seat?,
}

--[[ Private Functions ]]--
-- A point on the floor next to a building, given in that building's own space.
-- The height comes from the building rather than from a constant: the room floor is not flat data.
local function FloorPoint(part: BasePart, offset: Vector3): Vector3
	local world = part.CFrame * offset

	return Vector3.new(world.X, part.Position.Y - part.Size.Y / 2, world.Z)
end

-- Buildings are placed facing their front, so -Z in local space is always "in front of it".
local function FrontOf(part: BasePart, gap: number): Vector3
	return FloorPoint(part, Vector3.new(0, 0, -(part.Size.Z / 2 + gap)))
end

local function GetPart(player: Player, buildingId: string): BasePart?
	local building = BuildingHandler:GetBuilding(player, buildingId)

	return building and building.Part
end

local function DisplaySpot(player: Player, customer: any): Spot?
	local bought = math.clamp(
		UpgradeHandler:GetLevel(player, FoodPresentation.DisplayUpgrade),
		0,
		FoodPresentation.DisplayPedestals
	)
	if bought == 0 then
		return nil
	end
	local shopping = customer.State == "Shopping"
	local slot = if shopping then customer.DisplaySlot else math.random(2, bought + 1)
	local building = slot and BuildingHandler:GetBuilding(player, BuildingsConfig.GetId(DISPLAY_KIND, slot))
	if not building then
		return nil
	end
	local part = building.Part
	local food = building.FoodVisual
	if not food then
		return { Target = FrontOf(part, GuestsConfig.DisplayGap), LookAt = part.Position }
	end
	local centre = food.Frame.Position
	local forward = part.CFrame.LookVector
	local floorY = part.Position.Y - part.Size.Y / 2
	local approach = centre + forward * GuestsConfig.DisplayApproachDistance
	local target = if shopping then centre + forward * GuestsConfig.DisplayStandDistance else approach
	return {
		Target = Vector3.new(target.X, floorY, target.Z),
		Approach = if shopping then Vector3.new(approach.X, floorY, approach.Z) else nil,
		LookAt = centre,
	}
end

--[[ Handling ]]--
function Spots.Door(player: Player): BasePart?
	return GetPart(player, DOOR_ID)
end

-- The doorway faces OUT of the room, and a building's local -Z runs along its facing, so -Z is the
-- porch and +Z is the floor inside.
function Spots.Outside(door: BasePart): Vector3
	return FloorPoint(door, Vector3.new(0, 0, -GuestsConfig.SpawnDistance))
end

function Spots.Inside(door: BasePart): Vector3
	return FloorPoint(door, Vector3.new(0, 0, GuestsConfig.DoorStepDistance))
end

function Spots.Resolve(player: Player, customer: any, door: BasePart): Spot
	local tablePart = customer.TableId and GetPart(player, customer.TableId)
	local seat = tablePart
		and customer.SeatIndex
		and tablePart:FindFirstChild(`{TableConfig.SeatName}{customer.SeatIndex}`)
	if seat and seat:IsA("Seat") then
		local approach = seat.Position - seat.CFrame.LookVector * GuestsConfig.SeatGap
		return {
			-- Stops behind the chair; the seat itself puts the guest into it.
			Target = Vector3.new(approach.X, tablePart.Position.Y - tablePart.Size.Y / 2, approach.Z),
			LookAt = tablePart.Position,
			Seat = seat,
		}
	end

	if customer.Kind == DISPLAY_GUEST then
		local spot = DisplaySpot(player, customer)
		if spot then
			return spot
		end
	end

	local place = (customer.QueuePosition or 1) - 1
	local offset =
		Vector3.new(GuestsConfig.QueueSide + place * GuestsConfig.QueueGap, 0, -GuestsConfig.QueueOutsideDistance)

	return { Target = FloorPoint(door, offset), LookAt = door.Position }
end

return Spots
