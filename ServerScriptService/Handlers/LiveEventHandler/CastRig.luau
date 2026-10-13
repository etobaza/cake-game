--!strict
-- Giant cast avatars for the live event. Bodies are built from each member's UserId through the
-- guests' avatar cache (CustomerViewHandler/Appearance: pcall, per-server cache, retry cooldown),
-- scaled with Model:ScaleTo, fully anchored in their rest pose and made non-colliding. Display
-- names are read at runtime and stored as model attributes for the clients' banner and bubbles.
--
-- Every part is anchored on purpose. Avatar rigs use physical AnimationConstraint joints, and the
-- Humanoid drives them as a ragdoll while its root is pinned: a giant's body sags hundreds of studs
-- away from its root within seconds. The rig arrives in its rest pose, so anchoring it before it
-- enters the world keeps that pose exactly.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

--[[ Modules ]]--
local Appearance = require(ServerScriptService.Handlers.CustomerViewHandler.Appearance)
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "CastRig" })

--[[ Constants ]]--
-- The ground under a slot is found by a ray from this high above the stage origin, this long.
local GROUND_RAY_LIFT = 500
local GROUND_RAY_LENGTH = 1000

--[[ Private Variables ]]--
local displayNames: { [number]: string } = {}

--[[ Tables ]]--
local CastRig = {}

--[[ Private Functions ]]--
local function readDisplayName(userId: number): string?
	local cached = displayNames[userId]
	if cached then
		return cached
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, { userId })
	local name: string? = if ok and typeof(infos) == "table" and infos[1] then infos[1].DisplayName else nil
	if not name then
		local found, username = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = if found then username else nil
	end
	if name then
		displayNames[userId] = name
	end
	return name
end

-- World frame of slot `index` of `count`, facing the street, on whatever ground is under the
-- slot (the stage is rough terrain); the origin height is the fallback when nothing is there.
local function slotFrame(index: number, count: number, ignore: Instance): CFrame
	local stage = Config.Stage
	local facing = CFrame.lookAt(stage.Origin, Vector3.new(stage.LookAt.X, stage.Origin.Y, stage.LookAt.Z))
	local frame = facing * CFrame.new((index - (count + 1) / 2) * stage.Spacing, 0, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local start = frame.Position + Vector3.new(0, GROUND_RAY_LIFT, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -GROUND_RAY_LENGTH, 0), params)
	return if hit then frame + Vector3.new(0, hit.Position.Y - frame.Position.Y, 0) else frame
end

local function prepare(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	model.PrimaryPart = root

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	humanoid.EvaluateStateMachine = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	-- Far outside the streaming radius of most players, and still meant to be seen.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return humanoid
end

local function build(castId: string, index: number, count: number, ignore: Instance): Model?
	local member = Config.Cast[castId]
	local model = member and Appearance.Rig({ UserId = member.UserId, Name = "", Key = `cast_{castId}` })
	if not member or not model then
		return nil
	end
	local humanoid = prepare(model)
	if not humanoid then
		model:Destroy()
		Logger:Warn(`Cast {castId} has no humanoid rig.`)
		return nil
	end

	model.Name = `Cast_{castId}`
	model:ScaleTo(Config.Stage.Scale)
	-- Stand on the ground: an R15 root floats HipHeight plus half its own height above the floor,
	-- and ScaleTo has already scaled both.
	local root = model.PrimaryPart :: BasePart
	model:PivotTo(slotFrame(index, count, ignore) + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))

	model:SetAttribute("CastId", castId)
	model:SetAttribute("DisplayName", readDisplayName(member.UserId) or member.Role)
	return model
end

--[[ Handling ]]--
--- Builds the giants for `castIds` under `parent` in the background. `isCurrent` is checked after
--- every yield so a giant finished after its event ended is dropped instead of shown.
function CastRig.Spawn(castIds: { string }, parent: Instance, scope: any, isCurrent: () -> boolean): ()
	for index, castId in castIds do
		task.spawn(function(): ()
			local model = build(castId, index, #castIds, parent)
			if not model then
				return
			end
			if not isCurrent() then
				model:Destroy()
				return
			end
			model.Parent = parent
			scope:Add(model, "Destroy")
		end)
	end
end

return CastRig
