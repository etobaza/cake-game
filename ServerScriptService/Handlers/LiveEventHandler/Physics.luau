--!strict
-- Physics setup shared by the live event's world props (giants and cupcakes): inert anchored parts
-- and the exclude rays that place them.

--[[ Tables ]]--
local Physics = {}

--[[ Handling ]]--
--- Anchors every part under `root` and takes it out of collisions, touches and spatial queries.
function Physics.MakeInert(root: Instance): ()
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

--- Raycast params that skip `ignore` and everything under it.
function Physics.ExcludeParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

return Physics
