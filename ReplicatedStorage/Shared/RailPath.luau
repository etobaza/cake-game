--!strict
-- Shared route sampling keeps local presentation on the server's authored rail path.

export type Path = {
	Points: { { Position: Vector3, Distance: number } },
	Length: number,
	Stops: { number },
}

local RailPath = {}

function RailPath.Read(template: Instance, transform: CFrame): Path?
	local anchors = template:FindFirstChild("Anchors")
	local folder = anchors and anchors:FindFirstChild("GardenRailPath")
	if not folder then
		return nil
	end
	local points, total = {}, 0
	for index = 1, #folder:GetChildren() do
		local part = folder:FindFirstChild(tostring(index))
		if not part or not part:IsA("BasePart") then
			return nil
		end
		local point = (transform * part.CFrame).Position
		if index > 1 then
			total += (point - points[index - 1].Position).Magnitude
		end
		points[index] = { Position = point, Distance = total }
	end
	if #points < 2 or total <= 0 then
		return nil
	end
	local output = if anchors then anchors:FindFirstChild("rail_output") else nil
	local stops = {}
	-- The first delivery parks at the far end; later carts queue behind it.
	for index = 1, 4 do
		local attachment = output and output:FindFirstChild(`GardenProduce{index}`)
		if not attachment or not attachment:IsA("Attachment") then
			return nil
		end
		local position = (transform * attachment.WorldCFrame).Position
		position = Vector3.new(position.X, points[#points].Position.Y, position.Z)
		total += (position - points[#points].Position).Magnitude
		points[#points + 1] = { Position = position, Distance = total }
		stops[5 - index] = total
	end
	return { Points = points, Length = total, Stops = stops }
end

function RailPath.Sample(path: Path, distance: number): CFrame
	distance = math.clamp(distance, 0, path.Length)
	for index = 2, #path.Points do
		local previous, current = path.Points[index - 1], path.Points[index]
		local length = current.Distance - previous.Distance
		if distance > current.Distance or length <= 0 then
			continue
		end
		local position = previous.Position:Lerp(current.Position, (distance - previous.Distance) / length)
		return CFrame.lookAt(position, position + current.Position - previous.Position)
	end
	return CFrame.new(path.Points[#path.Points].Position)
end

return RailPath
