--!strict
-- Bodies are unique across the server. Visits are remembered per cafe owner across rejoins.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuestsConfig = require(ReplicatedStorage.Shared.Configs.Guests)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "Appearance" })

export type Identity = { UserId: number, Name: string, Key: string, Variant: number? }
type FriendList = { Items: { Identity }, Ready: boolean }

local Appearance = {}
local Friends: { [Player]: FriendList } = {}
local Taken: { [number]: Identity } = {}
local Visited: { [string]: { [number]: boolean } } = {}
local Failed: { [number]: number } = {}
local Rigs: { [number]: Model } = {}
local CacheOrder: { number } = {}
local NextVariant = 0

local function Generated(): Identity
	NextVariant += 1
	return { UserId = 0, Name = "", Key = `random_{NextVariant}`, Variant = NextVariant }
end

local function ReadFriends(player: Player): { Identity }
	local pages = Players:GetFriendsAsync(player.UserId)
	local items: { Identity } = {}
	local seen: { [number]: boolean } = {}
	while true do
		for _, item in pages:GetCurrentPage() do
			if #items >= GuestsConfig.Avatar.MaxFriends then
				break
			end
			if seen[item.Id] then
				continue
			end
			seen[item.Id] = true
			items[#items + 1] = {
				UserId = item.Id,
				Name = item.DisplayName or item.Username,
				Key = `user_{item.Id}`,
			}
		end
		if pages.IsFinished or #items >= GuestsConfig.Avatar.MaxFriends then
			break
		end
		pages:AdvanceToNextPageAsync()
	end
	return items
end

function Appearance.Load(player: Player): ()
	if Friends[player] then
		return
	end
	local state: FriendList = { Items = {}, Ready = false }
	Friends[player] = state
	for attempt = 1, GuestsConfig.Avatar.FriendLoadAttempts do
		local ok, result = pcall(ReadFriends, player)
		if Friends[player] ~= state then
			return
		end
		if ok and #result > 0 then
			state.Items = result
			break
		end
		if not ok then
			Logger:Warn(`Friends of {player.Name} unavailable: {result}`)
		end
		if attempt < GuestsConfig.Avatar.FriendLoadAttempts then
			task.wait(GuestsConfig.Avatar.FriendRetrySeconds)
			if Friends[player] ~= state then
				return
			end
		end
	end
	if #state.Items == 0 and RunService:IsStudio() then
		local snapshot = require(script.Parent.StudioFriends)[player.UserId]
		if snapshot then
			state.Items = snapshot
			Logger:Info(`Using Studio friend snapshot for {player.Name}: {#snapshot} friends`)
		end
	end
	state.Ready = true
end

function Appearance.Forget(player: Player): ()
	Friends[player] = nil
end

function Appearance.CanVisit(player: Player, identity: Identity): boolean
	local visits = Visited[identity.Key]
	return not visits or not visits[player.UserId]
end

function Appearance.Take(player: Player, allowGenerated: boolean?): Identity?
	local state = Friends[player]
	if not state or not state.Ready then
		return if allowGenerated then Generated() else nil
	end
	local available: { Identity } = {}
	for _, identity in state.Items do
		local id = identity.UserId
		if not Taken[id] and Appearance.CanVisit(player, identity) and (not Failed[id] or os.clock() >= Failed[id]) then
			available[#available + 1] = identity
		end
	end
	if #available == 0 then
		return Generated()
	end
	local identity = available[math.random(#available)]
	Taken[identity.UserId] = identity
	return identity
end

function Appearance.Visit(player: Player, identity: Identity): ()
	local visits = Visited[identity.Key]
	if not visits then
		visits = {}
		Visited[identity.Key] = visits
	end
	visits[player.UserId] = true
end

function Appearance.Release(_player: Player, identity: Identity): ()
	if Taken[identity.UserId] == identity then
		Taken[identity.UserId] = nil
	end
end

local function Template(userId: number): Model?
	local cached = Rigs[userId]
	if cached then
		return cached:Clone()
	end
	local ok, result = pcall(function()
		local description = if userId > 0
			then Players:GetHumanoidDescriptionFromUserIdAsync(userId)
			else Instance.new("HumanoidDescription")
		local built, model = pcall(function()
			return Players:CreateHumanoidModelFromDescriptionAsync(description, GuestsConfig.Avatar.RigType)
		end)
		description:Destroy()
		if not built then
			error(model)
		end
		return model
	end)
	if not ok then
		if userId > 0 then
			Failed[userId] = os.clock() + GuestsConfig.Avatar.AvatarRetrySeconds
		end
		Logger:Warn(`Avatar {userId} not loaded: {result}`)
		return nil
	end
	if Rigs[userId] then
		result:Destroy()
		return Rigs[userId]:Clone()
	end
	-- Guest owns animation and movement; avatar scripts must not install a second writer.
	for _, descendant in result:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	Rigs[userId] = result
	CacheOrder[#CacheOrder + 1] = userId
	while #CacheOrder > GuestsConfig.Avatar.MaxCachedRigs do
		local oldest = table.remove(CacheOrder, 1)
		if oldest then
			Rigs[oldest]:Destroy()
			Rigs[oldest] = nil
		end
	end
	return result:Clone()
end

function Appearance.Rig(identity: Identity): Model?
	local rig = Template(identity.UserId)
	if not rig then
		return nil
	end
	-- A missing classic outfit gets the authored fallback beneath any layered accessories.
	-- This also dresses the generated R15 body instead of relying on torso/leg colors.
	local shirt = rig:FindFirstChildOfClass("Shirt")
	if not shirt or shirt.ShirtTemplate == "" then
		local fallbackShirt = shirt or Instance.new("Shirt")
		fallbackShirt.ShirtTemplate = GuestsConfig.Avatar.FallbackShirt
		fallbackShirt.Parent = rig
	end
	local pants = rig:FindFirstChildOfClass("Pants")
	if not pants or pants.PantsTemplate == "" then
		local fallbackPants = pants or Instance.new("Pants")
		fallbackPants.PantsTemplate = GuestsConfig.Avatar.FallbackPants
		fallbackPants.Parent = rig
	end
	local variant = identity.Variant
	if variant then
		local skin = Color3.fromHSV(0.065, 0.15 + (variant % 5) * 0.1, 0.95 - (variant % 4) * 0.12)
		local torsoColor = Color3.fromHSV((variant * 0.61803398875) % 1, 0.55 + (variant % 3) * 0.12, 0.85)
		local legColor = Color3.fromHSV((variant * 0.38196601125) % 1, 0.45, 0.35 + (variant % 3) * 0.12)
		local colors = rig:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
		colors.HeadColor3 = skin
		colors.LeftArmColor3 = skin
		colors.RightArmColor3 = skin
		colors.TorsoColor3 = torsoColor
		colors.LeftLegColor3 = legColor
		colors.RightLegColor3 = legColor
		colors.Parent = rig
	end
	rig:SetAttribute("VisitorIdentity", identity.Key)
	rig:SetAttribute("AvatarUserId", identity.UserId)
	return rig
end

return Appearance
