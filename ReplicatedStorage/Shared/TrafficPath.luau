--!strict
-- Straights and semicircular turns form one continuous road loop.
local Config = require(script.Parent.Configs.Traffic)

export type Path = { Frame: CFrame, HalfLength: number, Radius: number, Height: number, Length: number }
local TrafficPath = {}

function TrafficPath.Build(roadFrame: CFrame, roadSize: Vector3, carHeight: number): Path
	local halfLength = math.max(1, roadSize.Z / 2 - Config.EndInset)
	local radius = math.max(1, roadSize.X * Config.LaneWidthFraction)
	return {
		Frame = roadFrame,
		HalfLength = halfLength,
		Radius = radius,
		Height = (roadSize.Y + carHeight) / 2 + Config.GroundClearance,
		Length = 4 * halfLength + 2 * math.pi * radius,
	}
end

function TrafficPath.Sample(path: Path, distance: number): CFrame
	local travel = (if Config.Reverse then -distance else distance) % path.Length
	local straight = 2 * path.HalfLength
	local arc = math.pi * path.Radius
	local position: Vector3
	local forward: Vector3
	if travel < straight then
		position = Vector3.new(path.Radius, path.Height, -path.HalfLength + travel)
		forward = Vector3.zAxis
	elseif travel < straight + arc then
		local angle = (travel - straight) / path.Radius
		position =
			Vector3.new(path.Radius * math.cos(angle), path.Height, path.HalfLength + path.Radius * math.sin(angle))
		forward = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	elseif travel < 2 * straight + arc then
		position = Vector3.new(-path.Radius, path.Height, path.HalfLength - (travel - straight - arc))
		forward = -Vector3.zAxis
	else
		local angle = (travel - 2 * straight - arc) / path.Radius
		position =
			Vector3.new(-path.Radius * math.cos(angle), path.Height, -path.HalfLength - path.Radius * math.sin(angle))
		forward = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	end
	if Config.Reverse then
		forward = -forward
	end
	local world = path.Frame:PointToWorldSpace(position)
	return CFrame.lookAt(world, world + path.Frame:VectorToWorldSpace(forward), path.Frame.UpVector)
		* Config.MeshRotation
end

-- Project a signal on either straight driving lane into the shared forward distance.
function TrafficPath.StopDistance(path: Path, localPosition: Vector3): number
	local z = math.clamp(localPosition.Z, -path.HalfLength, path.HalfLength)
	local distance = if localPosition.X > 0
		then path.HalfLength + z
		else 3 * path.HalfLength + math.pi * path.Radius - z
	return (if Config.Reverse then -distance else distance) % path.Length
end

return TrafficPath
