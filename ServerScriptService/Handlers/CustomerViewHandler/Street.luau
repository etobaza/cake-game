--!strict
-- One server crowd; cafes reserve existing bodies before committing orders.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Appearance = require(script.Parent.Appearance)
local Guest = require(script.Parent.Guest)
local StreetRoute = require(script.Parent.StreetRoute)
local GuestsConfig = require(ReplicatedStorage.Shared.Configs.Guests)
local Config = GuestsConfig.Street
local WalkSpeed = GuestsConfig.WalkSpeed
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "Street" })

export type Pedestrian = {
	Guest: Guest.Guest,
	Identity: Appearance.Identity,
	ReadyAt: number,
	Owner: Player?,
	Direction: number,
	Retiring: boolean,
}
type Base = {
	Folder: Folder,
	Route: StreetRoute.Route,
	Reserved: { [string]: Pedestrian },
	DemandUntil: number,
}
local Street = {}
local Bases: { [Player]: Base } = {}
local Actors: { [string]: Pedestrian } = {}
local Folder: Folder? = nil
local Circuit: { Vector3 } = {}
local Loading: {}? = nil
local NextSpawnAt = 0
local SourceIndex = 0

local function HasDestination(entry: Pedestrian): boolean
	for player in Bases do
		if Appearance.CanVisit(player, entry.Identity) then
			return true
		end
	end
	return false
end

local function Patrol(entry: Pedestrian, node: number): ()
	local guest = entry.Guest
	if guest.Destroyed or entry.Owner or #Circuit == 0 then
		return
	end
	local points: { Vector3 } = {}
	StreetRoute.Append(points, guest.Root.Position, Circuit[node])
	guest:WalkRoute(points, nil, function()
		if guest.Destroyed or entry.Owner then
			return
		end
		if not HasDestination(entry) then
			entry.Retiring = true
			guest:FadeOut()
			return
		end
		Patrol(entry, (node - 1 + entry.Direction) % #Circuit + 1)
	end)
end

function Street.Close(player: Player): ()
	if not Bases[player] then
		return
	end
	Bases[player] = nil
	for _, entry in Actors do
		if entry.Owner == player then
			entry.Guest:Destroy()
		end
	end
	if next(Bases) then
		return
	end
	for _, entry in Actors do
		entry.Guest:Destroy()
	end
	table.clear(Actors)
	if Folder then
		Folder:Destroy()
		Folder = nil
	end
	Circuit = {}
	Loading = nil
	NextSpawnAt = 0
end

function Street.Open(player: Player, folder: Folder, door: BasePart, porch: Vector3): ()
	Street.Close(player)
	local route = StreetRoute.Build(door, porch)
	if not route then
		Logger:Warn(`No authored sidewalk near {door:GetFullName()}`)
		return
	end
	if not Folder then
		Circuit = StreetRoute.Circuit()
		if #Circuit == 0 then
			Logger:Warn("Shared sidewalk circuit unavailable")
			return
		end
		local created = Instance.new("Folder")
		created.Name = Config.FolderName
		created.Parent = workspace
		Folder = created
	end
	Bases[player] = { Folder = folder, Route = route, Reserved = {}, DemandUntil = 0 }
end

-- CustomerHandler refreshes demand shortly before a due arrival, only while admission is open.
function Street.Prepare(player: Player): ()
	local base = Bases[player]
	if base then
		base.DemandUntil = os.clock() + Config.DemandSeconds
	end
end

local function NeedsSupply(player: Player, base: Base): boolean
	if os.clock() >= base.DemandUntil then
		return false
	end
	local nearby = 0
	for _, entry in Actors do
		if entry.Owner or entry.Retiring or entry.Guest.Destroyed or not entry.Guest.Model.Parent then
			continue
		end
		if not Appearance.CanVisit(player, entry.Identity) then
			continue
		end
		if StreetRoute.IsNearby(base.Route, entry.Guest.Root.Position) then
			nearby += 1
		end
	end
	return nearby < Config.NearbyPopulation
end

local function Spawn(player: Player, base: Base, approaching: boolean): ()
	local identity = Appearance.Take(player)
	if not identity then
		return
	end
	local rig = Appearance.Rig(identity)
	if not rig or Bases[player] ~= base or not base.Folder.Parent or not Folder then
		if rig then
			rig:Destroy()
		end
		Appearance.Release(player, identity)
		return
	end
	-- One circuit direction avoids head-on overlap on the narrow authored walking lane.
	local first: Vector3? = nil
	for _ = 1, 12 do
		local candidate = base.Route.First:Lerp(base.Route.Last, math.random())
		if approaching then
			local forward = Circuit[StreetRoute.NextNode(Circuit, candidate, 1)] - candidate
			if forward:Dot(base.Route.Center - candidate) < 0 then
				continue
			end
		end
		local clear = true
		for _, entry in Actors do
			local offset = (entry.Guest.Root.Position - candidate) * Vector3.new(1, 0, 1)
			if not entry.Guest.Destroyed and offset.Magnitude < Config.PersonalSpace + 2 then
				clear = false
				break
			end
		end
		if clear then
			first = candidate
			break
		end
	end
	if not first then
		rig:Destroy()
		Appearance.Release(player, identity)
		return
	end
	local ok, guest = pcall(Guest.new, `pedestrian_{identity.Key}`, identity.Name, rig, first, Folder)
	if not ok or not guest then
		rig:Destroy()
		Appearance.Release(player, identity)
		if not ok then
			Logger:Warn(`Pedestrian rig failed: {guest}`)
		end
		return
	end
	local entry: Pedestrian = {
		Guest = guest,
		Identity = identity,
		ReadyAt = os.clock() + Config.MinWalkSeconds,
		Owner = nil,
		Direction = 1,
		Retiring = false,
	}
	Actors[identity.Key] = entry
	guest.Janitor:Add(function()
		if Actors[identity.Key] == entry then
			Actors[identity.Key] = nil
		end
		Appearance.Release(player, identity)
	end)
	rig:SetAttribute("VisitorState", "Walking")
	Patrol(entry, StreetRoute.NextNode(Circuit, first, entry.Direction))
end

function Street.Update(): ()
	-- Keep a following gap without giving NPCs physical collisions that can wedge a doorway.
	for _, entry in Actors do
		local guest = entry.Guest
		if entry.Owner or guest.Destroyed or entry.Retiring then
			continue
		end
		local route = guest.Route
		local point = route and route.Points[route.Index]
		local heading = point and (point - guest.Root.Position) * Vector3.new(1, 0, 1)
		local speed = WalkSpeed
		if heading and heading.Magnitude > 0.01 then
			for _, other in Actors do
				if other == entry or other.Owner or other.Guest.Destroyed then
					continue
				end
				local delta = (other.Guest.Root.Position - guest.Root.Position) * Vector3.new(1, 0, 1)
				local ahead = delta:Dot(heading.Unit)
				local across = (delta - heading.Unit * ahead).Magnitude
				if ahead > 0 and across < 2.5 then
					speed = math.min(speed, math.max(0, (ahead - Config.PersonalSpace) * 2))
				end
			end
		end
		guest.Humanoid.WalkSpeed = speed
		if route and speed < WalkSpeed / 2 then
			route.Deadline = os.clock() + GuestsConfig.WalkTimeout
		end
	end
	local sources: { Player } = {}
	for player in Bases do
		sources[#sources + 1] = player
	end
	if #sources == 0 then
		return
	end
	table.sort(sources, function(a, b)
		return a.UserId < b.UserId
	end)
	local count, total = 0, 0
	for _, entry in Actors do
		if entry.Guest.Destroyed then
			continue
		end
		total += 1
		if entry.Owner or HasDestination(entry) then
			count += 1
		end
	end
	local target =
		math.min(Config.MaxPopulation, math.max(Config.MinimumPopulation, #sources * Config.PopulationPerBakery))
	if total >= Config.MaxPopulation or Loading or os.clock() < NextSpawnAt then
		return
	end
	local selected: number? = nil
	for step = 1, #sources do
		local index = (SourceIndex + step - 1) % #sources + 1
		local candidate = sources[index]
		if NeedsSupply(candidate, Bases[candidate]) then
			selected = index
			break
		end
	end
	if not selected and count >= target then
		return
	end
	SourceIndex = selected or SourceIndex % #sources + 1
	local player = sources[SourceIndex]
	local base = Bases[player]
	local ticket = {}
	Loading = ticket
	NextSpawnAt = os.clock() + Config.SpawnInterval
	task.spawn(function()
		-- Spawn returns nothing, so pcall's typed pack has no room for the error message.
		local ok, failure = pcall(Spawn :: any, player, base, selected ~= nil)
		if Loading == ticket then
			Loading = nil
		end
		if not ok then
			Logger:Warn(`Pedestrian creation failed: {failure}`)
		end
	end)
end

function Street.Take(player: Player, customerId: string): boolean
	local base = Bases[player]
	if not base or base.Reserved[customerId] then
		return false
	end
	local selected: Pedestrian? = nil
	local distance = math.huge
	local selectedRank = 2
	for _, entry in Actors do
		if entry.Owner or entry.Retiring or entry.Guest.Destroyed or os.clock() < entry.ReadyAt then
			continue
		end
		if not entry.Guest.Model.Parent then
			continue
		end
		if not Appearance.CanVisit(player, entry.Identity) then
			continue
		end
		local position = entry.Guest.Root.Position
		if not StreetRoute.IsNearby(base.Route, position) then
			continue
		end
		local gap = (position - base.Route.Center).Magnitude
		local rank = if entry.Identity.UserId > 0 then 0 else 1
		if rank < selectedRank or (rank == selectedRank and gap < distance) then
			selected = entry
			distance = gap
			selectedRank = rank
		end
	end
	if not selected then
		return false
	end
	selected.Owner = player
	base.Reserved[customerId] = selected
	Appearance.Visit(player, selected.Identity)
	local guest = selected.Guest
	guest.Humanoid.WalkSpeed = WalkSpeed
	guest.Route = nil
	guest.Model:SetAttribute("VisitorState", "Entering")
	guest.Model:SetAttribute("CustomerId", customerId)
	guest.Model:SetAttribute("CafeOwnerUserId", player.UserId)
	local takeaway = guest.Model:FindFirstChild("Takeaway")
	if takeaway then
		takeaway:Destroy()
	end
	guest.Janitor:Remove("CatCarrier")
	return true
end

function Street.Claim(player: Player, customerId: string): Pedestrian?
	local base = Bases[player]
	if not base then
		return nil
	end
	local entry = base.Reserved[customerId]
	base.Reserved[customerId] = nil
	return entry
end

function Street.Cancel(player: Player, customerId: string): ()
	local entry = Street.Claim(player, customerId)
	if entry then
		entry.Guest:Destroy()
	end
end

function Street.Enter(player: Player, guest: Guest.Guest, onArrive: () -> ()): ()
	local base = Bases[player]
	if not base then
		guest:Destroy()
		return
	end
	guest:WalkRoute(StreetRoute.Enter(base.Route, guest.Root.Position), nil, function()
		guest.Model:SetAttribute("VisitorState", "Customer")
		onArrive()
	end)
end

function Street.Exit(player: Player, guest: Guest.Guest, points: { Vector3 }, onReturned: (() -> ())?): ()
	local base = Bases[player]
	local identity = guest.Model:GetAttribute("VisitorIdentity")
	local entry = if typeof(identity) == "string" then Actors[identity] else nil
	if not base or not entry then
		guest:Exit(points, Config.ExitTimeout)
		return
	end
	guest.Model:SetAttribute("VisitorState", "Leaving")
	guest.ExitAt = os.clock() + Config.ExitTimeout
	StreetRoute.Append(points, points[#points] or guest.Root.Position, base.Route.Center)
	guest:WalkRoute(points, nil, function()
		if onReturned then
			onReturned()
		end
		if guest.Destroyed or not Folder then
			return
		end
		entry.Owner = nil
		entry.ReadyAt = os.clock() + Config.ReturnCooldownSeconds
		guest.ExitAt = nil
		guest.Model.Name = `pedestrian_{entry.Identity.Key}`
		guest.Model.Parent = Folder
		guest.Model:SetAttribute("CustomerId", nil)
		guest.Model:SetAttribute("CafeOwnerUserId", nil)
		guest.Model:SetAttribute("VisitorState", "Walking")
		Patrol(entry, StreetRoute.NextNode(Circuit, guest.Root.Position, entry.Direction))
	end)
end

return Street
