-- Real props for a building: the room's own table and chairs instead of a placeholder block.
-- Models clone from the template. Artist copies near the spawned slot come down; extras stay.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local CollisionConfig = require(_Configs.Collision)
local LoggerUtil = require(_Libs.Logger)

--[[ Constants ]]--
local SEAT_NAME = "Seat"
local SEAT_SIZE = Vector3.new(2, 0.2, 2)
-- Tables in the room sit ~24 studs apart; this only takes the copies that this building replaces.
local CLEAR_RADIUS = 10

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "Furniture" })

--[[ Tables ]]--
local Furniture = {}

export type Hidden = {
	Part: BasePart,
	Transparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
}

--[[ Private Functions ]]--
local function WorldPoint(inst: Instance): Vector3?
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end

	return nil
end

-- The point on the floor right under a model. GetBoundingBox measures in the pivot's frame, which on
-- these imported meshes reads a table as eleven studs tall, so the parts are measured directly.
local function GroundPoint(model: Model): Vector3
	local lowest, left, right, back, front = math.huge, math.huge, -math.huge, math.huge, -math.huge

	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end

		local frame = part.CFrame
		local reach = Vector3.new(
			math.abs(frame.RightVector.X) * part.Size.X
				+ math.abs(frame.UpVector.X) * part.Size.Y
				+ math.abs(frame.LookVector.X) * part.Size.Z,
			math.abs(frame.RightVector.Y) * part.Size.X
				+ math.abs(frame.UpVector.Y) * part.Size.Y
				+ math.abs(frame.LookVector.Y) * part.Size.Z,
			math.abs(frame.RightVector.Z) * part.Size.X
				+ math.abs(frame.UpVector.Z) * part.Size.Y
				+ math.abs(frame.LookVector.Z) * part.Size.Z
		) / 2

		lowest = math.min(lowest, frame.Position.Y - reach.Y)
		left = math.min(left, frame.Position.X - reach.X)
		right = math.max(right, frame.Position.X + reach.X)
		back = math.min(back, frame.Position.Z - reach.Z)
		front = math.max(front, frame.Position.Z + reach.Z)
	end

	return Vector3.new((left + right) / 2, lowest, (back + front) / 2)
end

-- These models come out of Blender with a tilted pivot, and their own facing is wherever their mesh
-- part looks. Both are normalised into the pivot: after this, one placement stands the model on a floor
-- point facing where it was told, with no per-model corrections.
-- PivotTo is not used: several imported meshes have MeshSize far larger than Size, and PivotTo follows
-- the mesh extents, so the visual flies off the building. Parts are moved by their Size box instead.
-- The parts also join the prop group on the way: to a guest this is furniture to walk through.
local function PlaceOnFloor(model: Model, placement: CFrame): ()
	local reference = model:FindFirstChildWhichIsA("BasePart", true)
	if not reference then
		return
	end

	model.PrimaryPart = nil

	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.CollisionGroup = CollisionConfig.Groups.Prop
			piece.Anchored = true
		end
	end

	local ground = GroundPoint(model)
	local look = reference.CFrame.LookVector * Vector3.new(1, 0, 1)
	local from = if look.Magnitude > 0.01 then CFrame.lookAt(ground, ground + look) else CFrame.new(ground)
	local delta = placement * from:Inverse()

	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.CFrame = delta * piece.CFrame
		end
	end
end

-- A guest is put into this seat by hand. Touch is off so it does not grab the player or another guest
-- walking past: seating is decided by the simulation, not by who brushed the chair first.
local function BuildSeat(chair: Model, placement: CFrame, lift: number): ()
	local seat = Instance.new("Seat")
	seat.Name = SEAT_NAME
	seat.Size = SEAT_SIZE
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false
	seat.Anchored = true
	seat.CFrame = placement * CFrame.new(0, lift, 0)
	seat.Parent = chair
end

-- Chairs stand around the building and look at it, so a guest sitting in one faces the table.
local function AddChair(
	part: BasePart,
	source: Instance,
	floor: CFrame,
	offset: Vector3,
	spec: BuildingsConfig.Furniture,
	lift: number?
): ()
	local chair = source:Clone() :: Model
	local spot = (floor * CFrame.new(offset)).Position
	local placement = CFrame.lookAt(spot, Vector3.new(floor.Position.X, spot.Y, floor.Position.Z))
		* CFrame.Angles(0, math.rad(spec.ChairYaw or 0), 0)

	PlaceOnFloor(chair, placement)
	chair.Parent = part

	if lift then
		BuildSeat(chair, placement, lift)
	end
end

--[[ Handling ]]--
-- Hides every part under a model, remembering what to put back. Used both for the artist copies a
-- spawned building replaces and for a tool that has been picked up off its stand.
function Furniture.Hide(root: Instance, hidden: { Hidden }): ()
	local pieces = if root:IsA("BasePart") then { root } else {}
	for _, piece in root:GetDescendants() do
		if piece:IsA("BasePart") then
			table.insert(pieces, piece)
		end
	end

	for _, piece in pieces do
		table.insert(hidden, {
			Part = piece,
			Transparency = piece.Transparency,
			CanCollide = piece.CanCollide,
			CanQuery = piece.CanQuery,
		})
		piece.Transparency = 1
		piece.CanCollide = false
		piece.CanQuery = false
	end
end

-- Hangs the real models on a building. The block itself stays as the anchor of the label and prompt.
function Furniture.Attach(part: BasePart, spec: BuildingsConfig.Furniture, template: Instance): ()
	local source = if spec.Asset
		then BuildingsConfig.FindAsset(spec.Asset)
		elseif spec.Model then BuildingsConfig.ResolvePath(template, spec.Model)
		else nil
	if not source then
		local label = spec.Asset or (spec.Model and table.concat(spec.Model, ".")) or "?"
		Logger:Warn(`Model {label} not found`)
		return
	end

	local floor = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)

	local live = source:Clone() :: Model
	if spec.DryAsset then
		live.Name = BuildingsConfig.LiveModelName
	end
	PlaceOnFloor(live, floor)
	live.Parent = part

	if spec.DryAsset then
		local drySource = BuildingsConfig.FindAsset(spec.DryAsset)
		if drySource then
			local dry = drySource:Clone() :: Model
			dry.Name = BuildingsConfig.DryModelName
			PlaceOnFloor(dry, floor)
			dry.Parent = part
		else
			Logger:Warn(`Dry model {spec.DryAsset} not found`)
		end
	end

	local chairSource = spec.Chair and BuildingsConfig.ResolvePath(template, spec.Chair)
	if not chairSource then
		return
	end

	for index, offset in (spec.Chairs or {}) :: { Vector3 } do
		-- Only the first chair carries a seat: one guest sits at a table, the others are dressing.
		AddChair(part, chairSource, floor, offset, spec, if index == 1 then spec.SeatLift else nil)
	end
end

-- The artist's extra tables stay until their own slot is spawned. Folders are skipped: Decoration
-- keeps a Chair folder of several models, and wiping the folder took every chair in the room.
-- The bakery is a live place instance, not a clone, so nothing is destroyed: the copies are hidden
-- and the returned list restores them through Furniture.Restore when the base unloads.
function Furniture.ClearNear(room: Instance, worldPosition: Vector3, spec: BuildingsConfig.Furniture): { Hidden }
	local hidden: { Hidden } = {}

	for _, path in (spec.Clear or {}) :: { { string } } do
		local holder = BuildingsConfig.ResolvePath(room, table.move(path, 1, #path - 1, 1, {}))
		if not holder then
			continue
		end

		local name = path[#path]
		for _, child in holder:GetDescendants() do
			if child.Name ~= name or child:IsA("Folder") then
				continue
			end

			local point = WorldPoint(child)
			if
				point
				and Vector3.new(point.X - worldPosition.X, 0, point.Z - worldPosition.Z).Magnitude <= CLEAR_RADIUS
			then
				Furniture.Hide(child, hidden)
			end
		end
	end

	return hidden
end

function Furniture.Restore(hidden: { Hidden }): ()
	for _, entry in hidden do
		if entry.Part.Parent then
			entry.Part.Transparency = entry.Transparency
			entry.Part.CanCollide = entry.CanCollide
			entry.Part.CanQuery = entry.CanQuery
		end
	end
end

return Furniture
