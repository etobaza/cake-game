--!strict
-- Admin abuse live event: owns the running event on this server, its cross-server relay and
-- schedule, and the giants and cupcake rain that live exactly as long as the event does.
--
-- An event is { Id, ScriptId, StartsAt }. Clients receive that state and derive every line from
-- Configs/AdminAbuse themselves, so the network never carries dialogue text.

--[[ Services ]]--
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local CastRig = require(script.CastRig)
local Config = require(_Shared.Configs.AdminAbuse)
local CupcakeRain = require(script.CupcakeRain)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Relay = require(script.Relay)
local Schedule = require(script.Schedule)
local Timeline = require(_Shared.LiveEventTimeline)
local Logger = require(_Shared.Libs.Logger).new({ name = "LiveEventHandler" })

--[[ Constants ]]--
local FOLDER_NAME = "LiveEvent"
local IDLE: Timeline.State = { Id = "", ScriptId = "", StartsAt = 0 }

--[[ Tables ]]--
local LiveEventHandler = {
	-- Cupcake income goes through EconomyHandler, and is only collected once DataHandler has loaded
	-- the owner's profile.
	dependencies = { "DataHandler", "EconomyHandler" },
}

--[[ Handling ]]--
function LiveEventHandler.OnInit(self: LiveEventHandler): ()
	self.State = nil
	self.Origin = false
	self.Finished = {}
	self.Scope = nil

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	self.Folder = folder
end

function LiveEventHandler.OnStart(self: LiveEventHandler): ()
	-- Late joiners ask for the state once their client handler is listening.
	Bus.LiveEvent.Get.OnServerInvoke = function(_player: Player): (string, string, number)
		local state = self.State or IDLE
		return state.Id, state.ScriptId, state.StartsAt
	end

	Relay.Listen(function(state: Timeline.State): ()
		self:Apply(state)
	end, function(id: string): ()
		self:Finish(id)
	end)

	-- Messages are best effort: the starting server repeats the state for servers that missed it.
	task.spawn(function(): ()
		while true do
			task.wait(Config.Relay.RebroadcastSeconds)
			local state = self.State
			if self.Origin and state and not Timeline.IsOver(state, workspace:GetServerTimeNow()) then
				Relay.PublishStart(state)
			end
		end
	end)

	if Config.Schedule.Enabled then
		task.spawn(function(): ()
			while true do
				local due = if self.State then nil else Schedule.Due(workspace:GetServerTimeNow())
				if due then
					self:Apply(due)
				end
				task.wait(Config.Schedule.CheckSeconds)
			end
		end)
	end
end

--- Starts `scriptId` on every server. Returns whether it started and a message for the admin.
function LiveEventHandler.Start(self: LiveEventHandler, scriptId: string): (boolean, string)
	local definition = Timeline.GetScript(scriptId)
	if not definition then
		return false, `Unknown live event script "{scriptId}".`
	end
	local current = self.State
	if current then
		return false, `"{current.ScriptId}" is already running. Stop it first.`
	end

	local state: Timeline.State = {
		Id = HttpService:GenerateGUID(false),
		ScriptId = scriptId,
		StartsAt = workspace:GetServerTimeNow() + Config.Relay.LeadSeconds,
	}
	self:Apply(state)
	self.Origin = true
	Relay.PublishStart(state)
	return true, `{definition.Name} starts in {Config.Relay.LeadSeconds} seconds on every server.`
end

--- Stops the running event on every server.
function LiveEventHandler.Stop(self: LiveEventHandler): (boolean, string)
	local state = self.State
	if not state then
		return false, "No live event is running."
	end
	Relay.PublishStop(state.Id)
	self:Finish(state.Id)
	return true, "The live event was stopped on every server."
end

function LiveEventHandler.IsLive(self: LiveEventHandler): boolean
	return Timeline.IsLive(self.State, workspace:GetServerTimeNow())
end

--- The customer type for a seated arrival when it should be a golden event guest, otherwise nil.
--- `countOfType` counts guests of a type currently in the bakery.
function LiveEventHandler.PickGuestType(
	self: LiveEventHandler,
	countOfType: (typeId: string) -> number
): string?
	local tuning = Config.Guests
	if not self:IsLive() or math.random() >= tuning.Chance then
		return nil
	end
	return if countOfType(tuning.TypeId) < tuning.MaxActive then tuning.TypeId else nil
end

-- Makes `state` the running event here: a different event replaces the current one, a copy of the
-- current one is ignored, and a finished one never comes back.
function LiveEventHandler.Apply(self: LiveEventHandler, state: Timeline.State): ()
	local now = workspace:GetServerTimeNow()
	if self.Finished[state.Id] or Timeline.IsOver(state, now) then
		return
	end
	local current = self.State
	if current and current.Id == state.Id then
		return
	end
	if current then
		self:Finish(current.Id)
	end

	self.State = state
	self.Origin = false
	local scope = Janitor.new()
	self.Scope = scope
	local function isCurrent(): boolean
		return self.State == state
	end

	CastRig.Spawn(Timeline.GetCast(state.ScriptId), self.Folder, scope, isCurrent)
	scope:Add(CupcakeRain.new(state, self.Folder), "Destroy")
	-- Not owned by the scope: Finish destroys the scope from inside this thread, and a stale
	-- timer is harmless because it checks the event first.
	task.delay(Timeline.EndsAt(state) - now, function(): ()
		if isCurrent() then
			self:Finish(state.Id)
		end
	end)

	Bus.LiveEvent.State:Fire(state.Id, state.ScriptId, state.StartsAt)
	Logger:Info(`Live event {state.ScriptId} ({state.Id}) starts at {state.StartsAt}.`)
end

-- Ends the event `id` here if it is the running one, and never lets it start again.
function LiveEventHandler.Finish(self: LiveEventHandler, id: string): ()
	self.Finished[id] = true
	local state = self.State
	if not state or state.Id ~= id then
		return
	end

	self.State = nil
	self.Origin = false
	local scope = self.Scope
	self.Scope = nil
	if scope then
		scope:Destroy()
	end
	Bus.LiveEvent.State:Fire(IDLE.Id, IDLE.ScriptId, IDLE.StartsAt)
	Logger:Info(`Live event {state.ScriptId} ({id}) ended.`)
end

export type LiveEventHandler = typeof(LiveEventHandler) & {
	State: Timeline.State?,
	-- This server started the current event and re-broadcasts it.
	Origin: boolean,
	-- Ids that ended or were stopped here; late relay copies of them are ignored.
	Finished: { [string]: boolean },
	Scope: any,
	Folder: Folder,
}

return LiveEventHandler :: LiveEventHandler
