--[[
	Replicated player data cache (Cloud + Session). Server pushes updates via Bus.Data.Update;
	this handler mirrors the server store and exposes read/subscribe APIs.

	After the first full snapshot of both stores, :IsReady() is true and :Get* methods return data.
	Paths are segment keys from root: empty {} = whole store; e.g. {"Inventory", "Ingredients"}.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bus = require(ReplicatedStorage.Shared.Bus)
local K = require(script.Config.Kinds)
local Signal = require(ReplicatedStorage.Shared.Libs.Signal)

type DataPath = { string | number }
type DataKind = "Cloud" | "Session"
type SubscribeChannel = DataKind | "Any"

type CloudData = typeof(require(script.Config.CloudData))
type SessionData = typeof(require(script.Config.SessionData))

export type PlayerData = {
	Cloud: CloudData,
	Session: SessionData,
}

local DataHandlerClient = {
	name = "DataClient",
	dependencies = {},
	priority = math.huge,
}

-- Helper function to set value by path in nested table
local function setValueByPath(tbl, path: DataPath, value)
	local current = tbl
	for i = 1, #path - 1 do
		local key = path[i]
		if current[key] == nil then
			current[key] = {}
		elseif type(current[key]) ~= "table" then
			error("Cannot create path: intermediate value is not a table")
		end
		current = current[key]
	end
	current[path[#path]] = value
end

-- Helper function to get value by path in nested table
local function getValueByPath(tbl, path: DataPath)
	local current = tbl
	for i = 1, #path do
		local key = path[i]
		if type(current) == "table" and current[key] ~= nil then
			current = current[key]
		else
			return
		end
	end
	return current
end

-- Compares the first #path segments; the caller decides how the lengths must line up.
local function pathMatches(path: DataPath, updatedPath: DataPath): boolean
	for i = 1, #path do
		if path[i] ~= updatedPath[i] then
			return false
		end
	end

	return true
end

function DataHandlerClient.OnStart(self: DataHandlerClient)
	self.Data = {
		Cloud = {},
		Session = {},
	} :: PlayerData

	self.DataUpdated = Signal() :: Signal.Signal<PlayerData>
	self.CloudDataUpdated = Signal() :: Signal.Signal<CloudData>
	self.SessionDataUpdated = Signal() :: Signal.Signal<SessionData>
	self.SpecificPathUpdated = Signal() :: Signal.Signal<DataPath, any, DataKind>

	self._initialDataReceived = false
	self._readySignal = Signal() :: Signal.Signal<PlayerData>

	self._receivedCloud = false
	self._receivedSession = false
	self._revision = 0

	self.DataUpdatedRemote = Bus.Data.Update.OnClientEvent:Connect(function(updatePacket)
		self:_handleDataUpdate(updatePacket)
	end)

	task.delay(3, function()
		if not self._initialDataReceived then
			self:_requestInitialData()
		end
	end)
end

--- Applies one store's deltas. An empty path means a full snapshot of that store.
function DataHandlerClient._applyStoreUpdates(self: DataHandlerClient, kind: DataKind, updates): boolean
	local hasUpdates = false
	local isCloud = kind == K.Cloud

	for _, update in updates do
		if not update.path then
			continue
		end

		if #update.path > 0 then
			setValueByPath(self.Data[kind], update.path, update.value)
		elseif isCloud then
			self.Data.Cloud = update.value
			self._receivedCloud = true
		else
			self.Data.Session = update.value
			self._receivedSession = true
		end

		hasUpdates = true
		self.SpecificPathUpdated:Fire(update.path, update.value, kind)
	end

	return hasUpdates
end

function DataHandlerClient._handleDataUpdate(self: DataHandlerClient, updatePacket)
	local revision = updatePacket.Revision
	if typeof(revision) == "number" then
		-- Drop stale/out-of-order packets so a delayed snapshot cannot wipe newer deltas.
		if revision <= self._revision then
			return
		end
		self._revision = revision
	end

	local hasUpdates = false

	if updatePacket.Cloud and #updatePacket.Cloud > 0 then
		hasUpdates = self:_applyStoreUpdates(K.Cloud, updatePacket.Cloud) or hasUpdates
		self.CloudDataUpdated:Fire(self.Data.Cloud)
	end

	if updatePacket.Session and #updatePacket.Session > 0 then
		hasUpdates = self:_applyStoreUpdates(K.Session, updatePacket.Session) or hasUpdates
		self.SessionDataUpdated:Fire(self.Data.Session)
	end

	if hasUpdates then
		if not self._initialDataReceived and self._receivedCloud and self._receivedSession then
			self._initialDataReceived = true
			self._readySignal:Fire(self.Data)
		end

		self.DataUpdated:Fire(self.Data)
	end
end

function DataHandlerClient._requestInitialData(self: DataHandlerClient)
	local maxRetries = 3
	local retryDelay = 1

	for retry = 1, maxRetries do
		local getCloud = self._receivedCloud and self.Data.Cloud or Bus.Data.GetCloud:Fire()
		local getSession = self._receivedSession and self.Data.Session or Bus.Data.GetSession:Fire()

		local updatePacket = {
			Cloud = {},
			Session = {},
		}

		if getCloud and not self._receivedCloud then
			table.insert(updatePacket.Cloud, { path = {}, value = getCloud })
		end

		if getSession and not self._receivedSession then
			table.insert(updatePacket.Session, { path = {}, value = getSession })
		end

		if #updatePacket.Cloud > 0 or #updatePacket.Session > 0 then
			self:_handleDataUpdate(updatePacket)
		end

		if self._receivedCloud and self._receivedSession then
			break
		end

		if retry < maxRetries then
			task.wait(retryDelay)
		end
	end
end

--- Block until both Cloud and Session snapshots exist, or a timeout. Default timeout is 10s.
--- Pass `math.huge` or a negative value for an unbounded wait (yields on the ready signal only).
function DataHandlerClient.WaitForData(self: DataHandlerClient, timeout: number?): PlayerData
	if self._initialDataReceived then
		return self.Data
	end

	local t = if timeout == nil then 10 else timeout
	if t < 0 or t == math.huge then
		self._readySignal:Wait()
		return self.Data
	end

	local done = false
	self._readySignal:Once(function()
		done = true
	end)
	task.delay(t, function()
		done = true
	end)
	while not done and not self._initialDataReceived do
		task.wait()
	end
	if not self._initialDataReceived then
		warn("[DataClient] Timeout waiting for initial data")
	end
	return self.Data
end

--- @param path Path from store root; `{}` returns the full Cloud or Session table.
--- @param dataType Defaults to Cloud.
function DataHandlerClient.GetData(self: DataHandlerClient, path: DataPath, dataType: DataKind?)
	dataType = dataType or K.Cloud

	if dataType ~= K.Cloud and dataType ~= K.Session then
		error(`Data type must be '{K.Cloud}' or '{K.Session}'`)
	end

	if not self._initialDataReceived then
		warn("[DataClient] Data not yet received from server")
		return
	end

	if #path == 0 then
		return self.Data[dataType]
	end

	return getValueByPath(self.Data[dataType], path)
end

--- Full snapshot `{ Cloud, Session }` (not the signal fields on the server). Nil if not :IsReady().
function DataHandlerClient.GetDataAll(self: DataHandlerClient): PlayerData?
	if not self._initialDataReceived then
		warn("[DataClient] Data not yet received from server")
		return
	end

	return self.Data
end

function DataHandlerClient.IsReady(self: DataHandlerClient)
	return self._initialDataReceived
end

--- @param dataType `K.Any` (default), `K.Cloud`, or `K.Session` — which store to match.
--- @param matchPrefix If true, any update whose path starts with `path` matches (e.g. list indices under a key).
function DataHandlerClient.SubscribeToPath(
	self: DataHandlerClient,
	path: DataPath,
	callback: (any, DataKind) -> (),
	dataType: SubscribeChannel?,
	matchPrefix: boolean?
): Signal.Connection<DataPath, any, DataKind>
	local channel = dataType or K.Any
	matchPrefix = matchPrefix or false

	return self.SpecificPathUpdated:Connect(function(updatedPath, value, updatedDataType)
		if channel ~= K.Any and channel ~= updatedDataType then
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

function DataHandlerClient.SubscribeToDataType(
	self: DataHandlerClient,
	dataType: DataKind,
	callback: (any) -> ()
): Signal.Connection<CloudData> | Signal.Connection<SessionData>
	if dataType == K.Cloud then
		return self.CloudDataUpdated:Connect(callback)
	elseif dataType == K.Session then
		return self.SessionDataUpdated:Connect(callback)
	else
		error(`Data type must be '{K.Cloud}' or '{K.Session}'`)
	end
end

function DataHandlerClient.SubscribeToAll(
	self: DataHandlerClient,
	callback: (PlayerData) -> ()
): Signal.Connection<PlayerData>
	return self.DataUpdated:Connect(callback)
end

function DataHandlerClient.DebugPrint(self: DataHandlerClient)
	print("=== Client Data ===")
	print("Cloud Data:", self.Data.Cloud)
	print("Session Data:", self.Data.Session)
	print("Initial Data Received:", self._initialDataReceived)
	print("Revision:", self._revision)
	print("===================")
end

export type DataHandlerClient = typeof(DataHandlerClient)
return DataHandlerClient
