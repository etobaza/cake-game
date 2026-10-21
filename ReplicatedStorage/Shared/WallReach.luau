--!strict
-- Interactions must not reach through the bakery's walls. Building prompts keep the engine's
-- RequiresLineOfSight off, because their invisible targets sit inside the artist's models and the
-- camera ray would hit those meshes; this check casts only against the room's shell instead.
-- The client hides a blocked prompt and the server refuses the action, from the same test.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local CollisionConfig = require(ReplicatedStorage.Shared.Configs.Collision)
local World = require(ReplicatedStorage.Shared.World)

--[[ Tables ]]--
local WallReach = {}

-- Wall folders per bakery root. The shell never changes at runtime, but with streaming a client can
-- receive a wall folder after its first lookup, so a folder's arrival drops the bakery's list.
local Walls: { [Instance]: { Instance } } = setmetatable({}, { __mode = "k" }) :: any
local Watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isWallFolder(instance: Instance): boolean
	return instance:IsA("Folder") and table.find(CollisionConfig.WallFolders, instance.Name) ~= nil
end

local function wallsOf(bakery: Instance): { Instance }
	local cached = Walls[bakery]
	if cached then
		return cached
	end
	if not Watched[bakery] then
		Watched[bakery] = true
		bakery.DescendantAdded:Connect(function(descendant: Instance): ()
			if isWallFolder(descendant) then
				Walls[bakery] = nil
			end
		end)
	end
	local folders: { Instance } = {}
	for _, descendant in bakery:GetDescendants() do
		if isWallFolder(descendant) then
			table.insert(folders, descendant)
		end
	end
	Walls[bakery] = folders
	return folders
end

-- The bakery a building target belongs to: its ancestor directly under World.Bakeries. Both the
-- Props folder BuildingHandler builds and the artist's dressed parts live inside it.
function WallReach.BakeryOf(part: Instance): Instance?
	local bakeries = World.Bakeries()
	if not bakeries then
		return nil
	end
	local current: Instance? = part
	while current and current.Parent ~= bakeries do
		current = current.Parent
	end
	return current
end

function WallReach.IsExempt(kindName: string?): boolean
	return kindName ~= nil and table.find(CollisionConfig.WallExemptKinds, kindName) ~= nil
end

-- True when no wall of the bakery stands between origin and target.
function WallReach.Clear(bakery: Instance, origin: Vector3, target: Vector3): boolean
	local walls = wallsOf(bakery)
	if #walls == 0 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = walls
	local offset = target - origin
	local result = workspace:Raycast(origin, offset, params)
	return result == nil or offset.Magnitude - result.Distance <= CollisionConfig.WallEmbedTolerance
end

return WallReach
