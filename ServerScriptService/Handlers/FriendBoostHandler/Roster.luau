--!strict
-- One cached check per unordered active-player pair. Departed instances cannot accept late results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Friends = require(ReplicatedStorage.Shared.Configs.Friends)

type Pair = {
	Key: string,
	First: Player,
	Second: Player,
	Friend: boolean,
	NextCheck: number,
	Queued: boolean,
	Pending: boolean,
	LoggedFailure: boolean,
}

local Roster = {}
Roster.__index = Roster

export type Roster = typeof(setmetatable(
	{} :: {
		Lookup: (Player, Player) -> boolean,
		Publish: (Player, number) -> (),
		Members: { [number]: Player },
		Counts: { [Player]: number },
		Pairs: { [string]: Pair },
		Queue: { Pair },
		Tasks: { [thread]: boolean },
		InFlight: number,
		Destroyed: boolean,
	},
	Roster
))

function Roster.new(lookup: (Player, Player) -> boolean, publish: (Player, number) -> ()): Roster
	return setmetatable({
		Lookup = lookup,
		Publish = publish,
		Members = {},
		Counts = {},
		Pairs = {},
		Queue = {},
		Tasks = {},
		InFlight = 0,
		Destroyed = false,
	}, Roster)
end

local function current(self: Roster, pair: Pair): boolean
	return not self.Destroyed
		and self.Pairs[pair.Key] == pair
		and self.Members[pair.First.UserId] == pair.First
		and self.Members[pair.Second.UserId] == pair.Second
end

function Roster.Recount(self: Roster): ()
	local counts: { [Player]: number } = {}
	for _, player in self.Members do
		counts[player] = 0
	end
	for _, pair in self.Pairs do
		if pair.Friend and current(self, pair) then
			counts[pair.First] += 1
			counts[pair.Second] += 1
		end
	end
	for player, count in counts do
		if self.Counts[player] ~= count then
			self.Counts[player] = count
			self.Publish(player, count)
		end
	end
end

local function startCheck(self: Roster, pair: Pair): ()
	pair.Pending = true
	self.InFlight += 1
	local worker: thread? = nil
	local timeout: thread? = nil
	local settled = false

	local function finish(success: boolean, result: unknown): ()
		if settled or self.Destroyed then
			return
		end
		settled = true
		for _, owned in { worker, timeout } do
			if not owned then
				continue
			end
			self.Tasks[owned] = nil
			if owned ~= coroutine.running() then
				task.cancel(owned)
			end
		end
		self.InFlight -= 1
		pair.Pending = false
		if current(self, pair) then
			pair.Friend = success and result == true
			pair.NextCheck = os.clock() + (if success then Friends.RefreshSeconds else Friends.RetrySeconds)
			if not success and not pair.LoggedFailure then
				pair.LoggedFailure = true
				print(`[FriendBoostHandler] Friendship check failed for {pair.Key}; retrying: {tostring(result)}`)
			elseif success then
				pair.LoggedFailure = false
			end
			self:Recount()
		end
		self:Pump()
	end

	worker = task.defer(function(): ()
		local success, result = pcall(self.Lookup, pair.First, pair.Second)
		finish(success, result)
	end)
	timeout = task.delay(Friends.CheckTimeoutSeconds, function(): ()
		finish(false, "Friendship check timed out")
	end)
	self.Tasks[worker :: thread] = true
	self.Tasks[timeout :: thread] = true
end

function Roster.Pump(self: Roster): ()
	while not self.Destroyed and self.InFlight < Friends.MaxConcurrentChecks and #self.Queue > 0 do
		local pair = table.remove(self.Queue, 1) :: Pair
		pair.Queued = false
		if not current(self, pair) then
			continue
		end
		startCheck(self, pair)
	end
end

function Roster.Add(self: Roster, player: Player): ()
	if self.Destroyed or self.Members[player.UserId] == player then
		return
	end
	local previous = self.Members[player.UserId]
	if previous then
		self:Remove(previous)
	end
	self.Members[player.UserId] = player
	for _, other in self.Members do
		if other == player then
			continue
		end
		local first, second = player, other
		if first.UserId > second.UserId then
			first, second = second, first
		end
		local key = `{first.UserId}:{second.UserId}`
		local pair: Pair = {
			Key = key,
			First = first,
			Second = second,
			Friend = false,
			NextCheck = 0,
			Queued = true,
			Pending = false,
			LoggedFailure = false,
		}
		self.Pairs[key] = pair
		self.Queue[#self.Queue + 1] = pair
	end
	self:Recount()
	self:Pump()
end

function Roster.Remove(self: Roster, player: Player): ()
	if self.Members[player.UserId] ~= player then
		return
	end
	self.Members[player.UserId] = nil
	self.Counts[player] = nil
	for key, pair in self.Pairs do
		if pair.First == player or pair.Second == player then
			self.Pairs[key] = nil
		end
	end
	-- Drop queued references immediately; in-flight calls keep only their bounded worker references.
	for index = #self.Queue, 1, -1 do
		if not current(self, self.Queue[index]) then
			table.remove(self.Queue, index)
		end
	end
	self:Recount()
end

function Roster.Tick(self: Roster): ()
	if self.Destroyed then
		return
	end
	local now = os.clock()
	for _, pair in self.Pairs do
		if pair.Pending or pair.Queued or pair.NextCheck > now then
			continue
		end
		-- A refresh must confirm the relationship again before it pays more money.
		pair.Friend = false
		pair.Queued = true
		self.Queue[#self.Queue + 1] = pair
	end
	self:Recount()
	self:Pump()
end

function Roster.GetCount(self: Roster, player: Player): number
	return self.Counts[player] or 0
end

function Roster.Destroy(self: Roster): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for worker in self.Tasks do
		task.cancel(worker)
	end
	table.clear(self.Tasks)
	table.clear(self.Queue)
	table.clear(self.Pairs)
	table.clear(self.Members)
	table.clear(self.Counts)
	self.InFlight = 0
end

return Roster
