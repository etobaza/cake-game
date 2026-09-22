--[[
	⚠️ WARNING: PROXIED DATA TABLES ⚠️

	This DataHandler uses a metatable proxy pattern to automatically track changes
	and sync data to clients. This has some important quirks you MUST be aware of:

	❌ DO NOT USE:
	- table.insert(proxyTable, value)  -- Bypasses metatable, NO sync triggered!
	- table.remove(proxyTable, index)  -- Bypasses metatable, NO sync triggered!
	- table.clone(proxyTable)          -- Clones proxy itself, NOT the actual data!
	- Writing to __originalTable / GetOriginalTable from game code — skips proxy sync
	- Bulk path writes — mutate through the proxy only

	✅ INSTEAD USE:
	- Direct assignment: data.Cloud.Inventory.Items[key] = value
	- For insert: data.Cloud.Inventory.Items[#data.Cloud.Inventory.Items + 1] = value
	- For remove: data.Cloud.Inventory.Items[key] = nil
	- For clone: DataHandler:GetOriginalTable + DataHandler.DeepClone (read/clone only)

	Ready API:
	- GetData(player) — non-yielding; nil if profile not attached yet
	- WaitForPlayer(player, timeout?) — yield until ready (default 10s)
	- PlayerReady — Signal fired when a player's profile attaches

	The proxy intercepts __newindex and __index to track changes, but Lua's built-in
	table functions bypass these metamethods and operate on the proxy table directly,
	which is EMPTY - the actual data is stored in the __originalTable metatable field.

	NOTE: Luau is based on Lua 5.1, which lacks the metamethods needed to make
	table.insert/table.remove work with proxies. Lua 5.2+ resolves this, but Roblox
	cannot simply update the language as it would introduce breaking changes.
	Luau does implement __len and __iter (replacing __pairs/__ipairs), but these
	don't help with table.insert/table.remove which use raw access internally.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local DataConfig = ReplicatedStorage.Handlers.DataHandlerClient.Config

local Bus = require(ReplicatedStorage.Shared.Bus)
local K = require(DataConfig.Kinds)
local GardenSave = require(script.Parent.BuildingHandler.GardenSave)
local ProgressReset = require(script.Parent.Parent.ProgressReset)
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)
local ProfileStore = require(ServerStorage.ServerPackages.profilestore)
local LoggerUtil = require(ReplicatedStorage.Shared.Libs.Logger)
local Signal = require(ReplicatedStorage.Shared.Libs.Signal)

local IS_STUDIO = RunService:IsStudio()

type DataPath = { string | number }
type DataKind = "Cloud" | "Session"
type SubscribeChannel = DataKind | "Any"

export type PendingUpdate = {
	dataType: DataKind,
	path: DataPath,
	value: any,
	timestamp: number,
}

export type PlayerUpdates = {
	updates: { PendingUpdate },
	lastFlush: number,
}

local DataHandler = {
	remotes = {},
	dependencies = {},
	priority = math.huge,

	StoreName = "dev_0",
	StudioSavingEnabled = true,

	-- Opt-in, Studio-only QA sessions; never changes the live store identity or saving policy.
	ForceMockData = IS_STUDIO and script:GetAttribute("AdminTestMockData") == true,
}

local Logger = LoggerUtil.new({ name = "DataHandler" }) :: any

local cloudDataTemplate = require(DataConfig.CloudData)
local sessionDataTemplate = require(DataConfig.SessionData)

export type PlayerSignals = {
	CloudDataUpdated: Signal.Signal<typeof(cloudDataTemplate)>,
	SessionDataUpdated: Signal.Signal<typeof(sessionDataTemplate)>,
	DataUpdated: Signal.Signal<PlayerData>,
	SpecificPathUpdated: Signal.Signal<DataPath, any, DataKind>,
}

export type PlayerData = {
	Cloud: typeof(cloudDataTemplate),
	Session: typeof(sessionDataTemplate),
} & PlayerSignals

-- Fired when a player's profile has attached and proxies are ready.
DataHandler.PlayerReady = Signal() :: Signal.Signal<Player, PlayerData>

local PlayerStore = ProfileStore.New(DataHandler.StoreName, cloudDataTemplate)

if (IS_STUDIO and not DataHandler.StudioSavingEnabled) or DataHandler.ForceMockData then
	PlayerStore = PlayerStore.Mock
end

local Profiles: { [Player]: typeof(PlayerStore:StartSessionAsync()) } = {}

local PENDING_UPDATES: { [Player]: PlayerUpdates } = {}
local UPDATE_THROTTLE: number = 1 / 30
local UPDATE_QUEUE: { [Player]: boolean } = {}
local REVISION: { [Player]: number } = {}

local DataUpdateRemote: any

local initialSent: { [Player]: { Session: boolean, Cloud: boolean } } = {}

local function deepClone(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end

	local tracker = seen or {}
	local existing = tracker[value]
	if existing ~= nil then
		return existing
	end

	local copy = {}
	tracker[value] = copy
	for k, v in value do
		copy[k] = deepClone(v, tracker)
	end
	return copy
end

DataHandler.DeepClone = deepClone

local function nextRevision(player: Player): number
	local rev = (REVISION[player] or 0) + 1
	REVISION[player] = rev
	return rev
end

-- Compares the first #path segments; the caller decides how the lengths must line up.
local function pathMatches(path: DataPath, other: DataPath): boolean
	for i = 1, #path do
		if path[i] ~= other[i] then
			return false
		end
	end

	return true
end

local function appendPath(basePath: DataPath, key: any): DataPath
	local path = table.clone(basePath)
	path[#path + 1] = key
	return path
end

--[[
	Flag changed paths and send at a fixed rate.
	Multiple changes in a frame batch into one client packet.
]]
local function flagDataForSync(player: Player, dataType: DataKind, path: DataPath, value: any)
	if not PENDING_UPDATES[player] then
		PENDING_UPDATES[player] = {
			updates = {},
			lastFlush = 0,
		}
	end

	local playerUpdates = PENDING_UPDATES[player]

	-- Deep clone tables so later mutations do not mutate the queued replication payload
	local valueToStore = value
	if type(value) == "table" then
		valueToStore = deepClone(value)
	end

	local existingIndex = nil
	for i, update in playerUpdates.updates do
		if update.dataType ~= dataType or #update.path ~= #path then
			continue
		end

		if pathMatches(path, update.path) then
			existingIndex = i
			break
		end
	end

	if existingIndex then
		playerUpdates.updates[existingIndex] = {
			dataType = dataType,
			path = path,
			value = valueToStore,
			timestamp = os.clock(),
		}
	else
		table.insert(playerUpdates.updates, {
			dataType = dataType,
			path = path,
			value = valueToStore,
			timestamp = os.clock(),
		})
	end

	if not UPDATE_QUEUE[player] then
		UPDATE_QUEUE[player] = true
	end
end

local function flushPlayerUpdates(player: Player)
	local playerUpdates = PENDING_UPDATES[player]
	if not playerUpdates or #playerUpdates.updates == 0 then
		UPDATE_QUEUE[player] = nil
		return
	end

	local currentTime = os.clock()

	if currentTime - playerUpdates.lastFlush < UPDATE_THROTTLE then
		return
	end

	local cloudUpdates = {}
	local sessionUpdates = {}

	for _, update in playerUpdates.updates do
		local bucket = if update.dataType == K.Cloud then cloudUpdates else sessionUpdates
		table.insert(bucket, {
			path = update.path,
			value = update.value,
		})
	end

	--[[
		Cloud - ProfileStore / DataStore
		Session - per play-session only, not saved
	]]

	local updatePacket = {
		Cloud = cloudUpdates,
		Session = sessionUpdates,
		Revision = nextRevision(player),
	}

	if #cloudUpdates > 0 or #sessionUpdates > 0 then
		DataUpdateRemote:FireClient(player, updatePacket)
	end

	playerUpdates.updates = {}
	playerUpdates.lastFlush = currentTime
	UPDATE_QUEUE[player] = nil
end

local function processUpdateQueue()
	for player in UPDATE_QUEUE do
		if player and player.Parent == Players then
			flushPlayerUpdates(player)
		else
			UPDATE_QUEUE[player] = nil
			PENDING_UPDATES[player] = nil
		end
	end
end

-- Fans one write out to the per-path, per-store and whole-profile signals.
local function notifyDataChanged(playerData: PlayerData, dataType: DataKind, path: DataPath, value: any)
	playerData.SpecificPathUpdated:Fire(path, value, dataType)

	if dataType == K.Cloud then
		playerData.CloudDataUpdated:Fire(playerData.Cloud)
	elseif dataType == K.Session then
		playerData.SessionDataUpdated:Fire(playerData.Session)
	end

	playerData.DataUpdated:Fire(playerData)
end

--[[
	Proxy wrapper around ProfileStore.Data / SessionData.
	Metatable tracks nested writes and flags them for client sync.
]]
local function createProxy(t: any, player: Player, dataType: DataKind, basePath: DataPath, handler: any): any
	basePath = basePath or {}

	local proxy = {}
	local metatable = {}

	metatable.__originalTable = t
	metatable.__player = player
	metatable.__dataType = dataType
	metatable.__basePath = basePath
	metatable.__nestedProxies = {}
	metatable.__handler = handler

	metatable.__index = function(_, key)
		local value = t[key]
		if type(value) ~= "table" or getmetatable(value) then
			return value
		end

		local nested = metatable.__nestedProxies[key]
		if not nested then
			nested = createProxy(value, player, dataType, appendPath(basePath, key), handler)
			metatable.__nestedProxies[key] = nested
		end

		return nested
	end

	metatable.__newindex = function(_, key, value)
		t[key] = value

		local fullPath = appendPath(basePath, key)

		if type(value) == "table" and not getmetatable(value) then
			metatable.__nestedProxies[key] = createProxy(value, player, dataType, appendPath(basePath, key), handler)
		else
			metatable.__nestedProxies[key] = nil
		end

		flagDataForSync(player, dataType, fullPath, value)

		local playerData = handler.Data[player]
		if playerData then
			notifyDataChanged(playerData, dataType, fullPath, value)
		end
	end

	metatable.__len = function()
		local count = 0
		for _ in metatable.__originalTable do
			count = count + 1
		end
		return count
	end

	-- Generalized iteration expects an iterator function, not the table itself.
	metatable.__iter = function()
		return next, metatable.__originalTable
	end

	return setmetatable(proxy, metatable)
end

-- Both stores as one full snapshot, sent once the profile is attached.
local function sendInitialSnapshot(handler: any, player: Player)
	task.defer(function()
		local current = handler.Data[player]
		if not current then
			return
		end

		local originalData = getmetatable(current.Cloud).__originalTable
		local originalSessionData = getmetatable(current.Session).__originalTable

		DataUpdateRemote:FireClient(player, {
			Cloud = { { path = {}, value = deepClone(originalData) } },
			Session = { { path = {}, value = deepClone(originalSessionData) } },
			Revision = nextRevision(player),
		})
	end)
end

function DataHandler.OnInit(self: DataHandler)
	DataUpdateRemote = Bus.Data.Update

	self.Data = {} :: { [Player]: PlayerData }

	local function PlayerAdded(player: Player)
		initialSent[player] = {
			Session = false,
			Cloud = false,
		}

		-- ProfileStore keeps retrying the session until this says the player is gone.
		local function cancelSession(): boolean
			return player.Parent ~= Players
		end

		local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, { Cancel = cancelSession })

		if profile == nil then
			Logger:Warn(`Profile load fail for {player.DisplayName}`)
			player:Kick(`Profile load fail - Please rejoin`)
			return
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()

		-- Deep-clone session template so players never share nested tables
		profile.SessionData = deepClone(sessionDataTemplate)

		local playerData: PlayerData = {
			Cloud = createProxy(profile.Data, player, K.Cloud, {}, self),
			Session = createProxy(profile.SessionData, player, K.Session, {}, self),
			CloudDataUpdated = Signal() :: Signal.Signal<typeof(cloudDataTemplate)>,
			SessionDataUpdated = Signal() :: Signal.Signal<typeof(sessionDataTemplate)>,
			DataUpdated = Signal() :: Signal.Signal<PlayerData>,
			SpecificPathUpdated = Signal() :: Signal.Signal<DataPath, any, DataKind>,
		}
		self.Data[player] = playerData
		if playerData.Cloud.ProgressResetPending then
			ProgressReset.Apply(playerData.Cloud, deepClone(cloudDataTemplate))
			Logger:Info(`Progress reset applied for {player.Name}`)
		end
		GardenSave.Migrate(playerData)
		TutorialPolicy.Migrate(playerData)
		profile.OnLastSave:Connect(function()
			GardenSave.Recover(playerData)
		end)

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			PENDING_UPDATES[player] = nil
			UPDATE_QUEUE[player] = nil
			REVISION[player] = nil
			self.Data[player] = nil
			local message = if playerData.Cloud.ProgressResetPending
				then "Progress reset requested. Rejoin for a fresh start. Paid ownership is preserved."
				else "Profile session end - Please rejoin"
			player:Kick(message)
		end)

		if player.Parent ~= Players then
			profile:EndSession()
			return
		end

		Profiles[player] = profile
		Logger:Info(`Profile loaded for {player.DisplayName}!`)

		DataHandler.PlayerReady:Fire(player, playerData)
		sendInitialSnapshot(self, player)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(PlayerAdded, player)
	end

	Players.PlayerAdded:Connect(PlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		local profile = Profiles[player]
		if profile ~= nil then
			GardenSave.Recover(self.Data[player])
			profile:EndSession()
		end
		PENDING_UPDATES[player] = nil
		UPDATE_QUEUE[player] = nil
		REVISION[player] = nil
		initialSent[player] = nil
		self.Data[player] = nil
	end)

	local getCloud = Bus.Data.GetCloud
	local getSession = Bus.Data.GetSession

	getSession.OnServerInvoke = function(plr)
		local profile = self:GetData(plr)
		if profile then
			initialSent[plr].Session = true
			return getmetatable(profile.Session).__originalTable
		end
		return nil
	end

	getCloud.OnServerInvoke = function(plr)
		local profile = self:GetData(plr)
		if profile then
			initialSent[plr].Cloud = true
			return getmetatable(profile.Cloud).__originalTable
		end
		return nil
	end

	RunService.Heartbeat:Connect(processUpdateQueue)
end

function DataHandler.OnStart(_self: DataHandler) end

--- Non-yielding. Returns live proxy + signals, or nil if profile not attached yet.
function DataHandler.GetData(self: DataHandler, player: Player): PlayerData?
	return self.Data[player]
end

--- Yield until the player's profile is ready, or timeout (default 10s).
--- Pass math.huge or a negative value for an unbounded wait.
function DataHandler.WaitForPlayer(self: DataHandler, player: Player, timeout: number?): PlayerData?
	local existing = self.Data[player]
	if existing then
		return existing
	end

	local t = if timeout == nil then 10 else timeout
	local result: PlayerData? = nil

	local connection = DataHandler.PlayerReady:Connect(function(readyPlayer: Player, playerData: PlayerData)
		if readyPlayer == player then
			result = playerData
		end
	end)

	-- Cover race: profile attached between first GetData check and Connect
	result = result or self.Data[player]

	-- An unbounded wait is the same loop with a deadline that never arrives.
	local deadline = if t < 0 or t == math.huge then math.huge else os.clock() + t
	while result == nil and player.Parent == Players and os.clock() < deadline do
		task.wait()
	end

	connection:Disconnect()

	if result == nil then
		result = self.Data[player]
	end

	if result == nil then
		Logger:Warn(`WaitForPlayer timed out for {player}`)
	end

	return result
end

--- Raw data table behind the proxy (read/clone only — do not mutate from game code).
function DataHandler.GetOriginalTable(self: DataHandler, player: Player, dataType: DataKind): any
	local profile = self:GetData(player)
	if not profile then
		return nil
	end

	if dataType == K.Cloud then
		return getmetatable(profile.Cloud).__originalTable
	else
		return getmetatable(profile.Session).__originalTable
	end
end

-- Finish the active session normally. The next load resets before any gameplay state is bound.
function DataHandler.RequestProgressReset(self: DataHandler, player: Player): string
	local profile = Profiles[player]
	local data = self:GetData(player)
	if not profile or not profile:IsActive() or not data then
		return "Player data is not ready."
	end
	if data.Cloud.ProgressResetPending then
		return "A progress reset is already pending. Rejoin the game."
	end

	data.Cloud.ProgressResetPending = true
	Logger:Info(`Progress reset requested for {player.Name}`)
	profile:EndSession()
	return `Progress reset requested for {player.Name}. Rejoin for a fresh start. Paid ownership is preserved.`
end

function DataHandler.WipeData(self: DataHandler, player: Player)
	local profile_key = `{player.UserId}`
	local profile = Profiles[player]
	if profile then
		profile:EndSession()
	end
	PlayerStore:RemoveAsync(profile_key)
	PENDING_UPDATES[player] = nil
	UPDATE_QUEUE[player] = nil
	REVISION[player] = nil
	self.Data[player] = nil
end

function DataHandler:SetUpdateThrottle(throttle: number): ()
	UPDATE_THROTTLE = throttle
	Logger:Info(`Update throttle set to {throttle} seconds`)
end

function DataHandler.ForceSync(_self: DataHandler, player: Player?): ()
	if player then
		flushPlayerUpdates(player)
		return
	end

	for playerKey in UPDATE_QUEUE do
		if playerKey and playerKey.Parent == Players then
			flushPlayerUpdates(playerKey)
		end
	end
end

-- Flush older deltas before sending the current full state through the existing revision channel.
function DataHandler.ResendSnapshot(self: DataHandler, player: Player): ()
	flushPlayerUpdates(player)
	sendInitialSnapshot(self, player)
end

function DataHandler.GetSyncStats(_self: DataHandler)
	local stats = {
		totalPlayers = 0,
		playersWithUpdates = 0,
		totalPendingUpdates = 0,
	}

	for player, data in PENDING_UPDATES do
		if not player or player.Parent ~= Players then
			continue
		end

		stats.totalPlayers += 1
		if #data.updates == 0 then
			continue
		end

		stats.playersWithUpdates += 1
		stats.totalPendingUpdates += #data.updates
	end

	return stats
end

function DataHandler.SubscribeToDataType(
	self: DataHandler,
	player: Player,
	channel: DataKind,
	callback: (any) -> ()
): Signal.Connection<typeof(cloudDataTemplate)>? | Signal.Connection<typeof(sessionDataTemplate)>?
	local playerData = self:GetData(player)
	if not playerData then
		return nil
	end

	if channel == K.Cloud then
		return playerData.CloudDataUpdated:Connect(callback)
	elseif channel == K.Session then
		return playerData.SessionDataUpdated:Connect(callback)
	else
		error(`Data type must be '{K.Cloud}' or '{K.Session}'`)
	end
end

function DataHandler.SubscribeToAll(
	self: DataHandler,
	player: Player,
	callback: (PlayerData) -> ()
): Signal.Connection<PlayerData>?
	local playerData = self:GetData(player)
	if not playerData then
		return nil
	end

	return playerData.DataUpdated:Connect(callback)
end

--- @param dataType `K.Any` (default), `K.Cloud`, or `K.Session` — which store to match.
function DataHandler.SubscribeToPath(
	self: DataHandler,
	player: Player,
	path: DataPath,
	callback: (any, DataKind) -> (),
	dataType: SubscribeChannel?,
	matchPrefix: boolean?
): Signal.Connection<DataPath, any, DataKind>?
	local channel: SubscribeChannel = dataType or K.Any
	matchPrefix = matchPrefix or false

	local playerData = self:GetData(player)
	if not playerData then
		return nil
	end

	return playerData.SpecificPathUpdated:Connect(function(updatedPath, value, updatedDataType)
		local channelMatches = channel == K.Any or channel == updatedDataType
		if not channelMatches then
			return
		end

		local lengthFits = if matchPrefix then #updatedPath >= #path else #updatedPath == #path
		if not lengthFits then
			return
		end

		if pathMatches(path, updatedPath) then
			callback(value, updatedDataType)
		end
	end)
end

export type DataHandler = typeof(DataHandler)
return DataHandler :: DataHandler
