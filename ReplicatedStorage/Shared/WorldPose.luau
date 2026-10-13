--!strict
-- Interaction geometry remains at the authored doorway while its cosmetic leaves move locally.
local WorldPose = {
	PivotAttribute = "InteractionRestPivot",
	FrameAttribute = "InteractionRestFrame",
	SizeAttribute = "InteractionRestSize",
}

function WorldPose.Pivot(model: Model): CFrame
	local pivot = model:GetAttribute(WorldPose.PivotAttribute)
	return if typeof(pivot) == "CFrame" then pivot else model:GetPivot()
end

function WorldPose.Bounds(model: Model): (CFrame, Vector3)
	local frame = model:GetAttribute(WorldPose.FrameAttribute)
	local size = model:GetAttribute(WorldPose.SizeAttribute)
	if typeof(frame) == "CFrame" and typeof(size) == "Vector3" then
		return frame, size
	end
	return model:GetBoundingBox()
end

return WorldPose
