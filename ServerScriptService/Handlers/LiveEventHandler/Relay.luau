--!strict
-- Cross-server start/stop of the live event over one MessagingService topic.
--
-- Payloads are compact ids and a start time, never dialogue text (the message limit is 1 kB and
-- every server resolves lines from config). Delivery is best effort: LiveEventHandler re-broadcasts
-- the running state, and a server that publishes also applies the change itself, so its own echo
-- is a duplicate it already ignores. In Studio, publishing may fail; the local event still runs.

--[[ Services ]]--
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.AdminAbuse)
local Timeline = require(ReplicatedStorage.Shared.LiveEventTimeline)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "LiveEventRelay" })

--[[ Constants ]]--
local KIND_START = "s"
local KIND_STOP = "x"
local MAX_ID_LENGTH = 64

--[[ Tables ]]--
local Relay = {}

--[[ Private Functions ]]--
local function publish(payload: { [string]: any }): ()
	task.spawn(function(): ()
		local ok, result = pcall(MessagingService.PublishAsync, MessagingService, Config.Relay.Topic, payload)
		if not ok then
			Logger:Warn(`Publish failed: {result}`)
		end
	end)
end

local function readId(value: any): string?
	return if typeof(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH then value else nil
end

-- A start time a real start could carry: not past the end of the script, and no further ahead than
-- the start lead plus clock slack between servers. Anything else is stale or forged.
local function readStartsAt(value: any, duration: number): number?
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local relay = Config.Relay
	if value < now - duration or value > now + relay.LeadSeconds + relay.StartSlackSeconds then
		return nil
	end
	return value
end

--[[ Handling ]]--
function Relay.PublishStart(state: Timeline.State): ()
	publish({ k = KIND_START, i = state.Id, s = state.ScriptId, t = state.StartsAt })
end

function Relay.PublishStop(id: string): ()
	publish({ k = KIND_STOP, i = id })
end

--- Subscribes in the background and keeps retrying; every payload is validated before use.
function Relay.Listen(onStart: (state: Timeline.State) -> (), onStop: (id: string) -> ()): ()
	local function receive(message: any): ()
		local data = if typeof(message) == "table" then message.Data else nil
		if typeof(data) ~= "table" then
			return
		end
		local id = readId(data.i)
		if not id then
			return
		end

		if data.k == KIND_STOP then
			onStop(id)
			return
		end
		local scriptId = readId(data.s)
		local definition = if data.k == KIND_START and scriptId then Timeline.GetScript(scriptId) else nil
		if not scriptId or not definition then
			return
		end
		local startsAt = readStartsAt(data.t, definition.Duration)
		if not startsAt then
			return
		end
		onStart({ Id = id, ScriptId = scriptId, StartsAt = startsAt })
	end

	task.spawn(function(): ()
		while true do
			local ok, result = pcall(MessagingService.SubscribeAsync, MessagingService, Config.Relay.Topic, receive)
			if ok then
				return
			end
			Logger:Warn(`Subscribe failed, retrying in {Config.Relay.SubscribeRetrySeconds} s: {result}`)
			task.wait(Config.Relay.SubscribeRetrySeconds)
		end
	end)
end

return Relay
