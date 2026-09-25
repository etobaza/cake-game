--!strict
-- A short, collision-checked adjustment puts the broom stroke immediately beside the puddle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.DayCycle).Sweep

local SweepPlacement = {}
local HORIZONTAL = Vector3.new(1, 0, 1)
local EPSILON = 0.001

function SweepPlacement.Goal(rootFrame: CFrame, spillFrame: CFrame, spillSize: Vector3): CFrame
	local outward = (rootFrame.Position - spillFrame.Position) * HORIZONTAL
	if outward.Magnitude < EPSILON then
		outward = -rootFrame.LookVector * HORIZONTAL
	end
	if outward.Magnitude < EPSILON then
		outward = Vector3.zAxis
	end
	outward = outward.Unit
	local direction = spillFrame:VectorToObjectSpace(outward)
	-- The floor mesh has a rounded footprint; use its rotated X/Z ellipse, not a fixed radius.
	local halfX = math.max(spillSize.X / 2, EPSILON)
	local halfZ = math.max(spillSize.Z / 2, EPSILON)
	local radius = 1 / math.sqrt((direction.X / halfX) ^ 2 + (direction.Z / halfZ) ^ 2)
	local edge = spillFrame.Position + outward * (radius + Config.EdgeClearance)
	local position = Vector3.new(edge.X, rootFrame.Position.Y, edge.Z)
	return CFrame.lookAt(position, position - outward)
end

function SweepPlacement.Resolve(character: Model, root: BasePart, humanoid: Humanoid, spill: BasePart): CFrame?
	if (root.Position - spill.Position).Magnitude > Config.PromptDistance then
		return nil
	end
	local goal = SweepPlacement.Goal(root.CFrame, spill.CFrame, spill.Size)
	if (goal.Position - root.Position).Magnitude > Config.MaxAdjustment then
		return nil
	end

	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { character, spill }
	ray.RespectCanCollide = true
	ray.CollisionGroup = root.CollisionGroup
	local down = -Vector3.yAxis * (humanoid.HipHeight + root.Size.Y / 2 + Config.FloorProbeExtra)
	local currentFloor = workspace:Raycast(root.Position, down, ray)
	local nextFloor = workspace:Raycast(goal.Position, down, ray)
	if not currentFloor or not nextFloor then
		return nil
	end
	local heightChange = nextFloor.Position.Y - currentFloor.Position.Y
	if math.abs(heightChange) > Config.FloorTolerance then
		return nil
	end
	goal += Vector3.yAxis * heightChange

	-- Check the torso volume through the adjustment and at its endpoint, including walls.
	local bodySize = Vector3.new(math.max(root.Size.X, 1.5), root.Size.Y + 1, math.max(root.Size.Z, 1.5))
	local movement = goal.Position - root.Position
	if movement.Magnitude > EPSILON and workspace:Blockcast(root.CFrame, bodySize, movement, ray) then
		return nil
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = ray.FilterType
	overlap.FilterDescendantsInstances = ray.FilterDescendantsInstances
	overlap.RespectCanCollide = true
	overlap.CollisionGroup = root.CollisionGroup
	overlap.MaxParts = 1
	if #workspace:GetPartBoundsInBox(goal, bodySize, overlap) > 0 then
		return nil
	end
	return goal
end

return SweepPlacement
