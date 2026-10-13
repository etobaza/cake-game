--!strict
-- Admin abuse live event on the client. The server sends only { id, script id, start time }; the
-- current line, the countdown and the time left come from LiveEventTimeline and the shared clock,
-- so a late joiner lands on the same line as everyone else without per-line traffic.
--
-- Each line is shown three ways: a speech bubble over the speaking giant, a system line in chat,
-- and the HUD banner with the speaker's headshot (readable when the chat is hidden).

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Banner = require(script.Banner)
local Bus = require(_Shared.Bus)
local Config = require(_Shared.Configs.AdminAbuse)
local FeedbackHandler = require(_Handlers.FeedbackHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Rain = require(script.Rain)
local Speech = require(script.Speech)
local Timeline = require(_Shared.LiveEventTimeline)

--[[ Constants ]]--
local FOLDER_NAME = "LiveEvent"
local COIN_PITCH = 1.2

--[[ Tables ]]--
local LiveEventHandler = {
	-- Collected cupcakes fly into the HUD through the sale coin effect.
	dependencies = { "FeedbackHandler" },
}

--[[ Private Functions ]]--
local function speakerName(folder: Instance, castId: string): string
	local giant = folder:FindFirstChild(`Cast_{castId}`)
	local name = giant and giant:GetAttribute("DisplayName")
	return if typeof(name) == "string" and name ~= "" then name else Config.Cast[castId].Role
end

local function postToChat(name: string, text: string): ()
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if not system or not system:IsA("TextChannel") then
		return
	end
	local speech = Config.Speech
	local color = speech.ChatColor:ToHex()
	system:DisplaySystemMessage(`<font color="#{color}"><b>[{speech.ChatTag}] {name}:</b></font> {text}`)
end

--[[ Handling ]]--
function LiveEventHandler.OnStart(self: LiveEventHandler): ()
	self.State = nil
	self.LineIndex = nil
	self.Owner = Janitor.new()
	self.Folder = workspace:WaitForChild(FOLDER_NAME)
	self.Banner = self.Owner:Add(Banner.new(), "Destroy")
	self.Speech = self.Owner:Add(Speech.new(self.Folder), "Destroy")
	self.Owner:Add(Rain.new(self.Folder), "Destroy")

	local pushed = false
	self.Owner:Add(
		Bus.LiveEvent.State.OnClientEvent:Connect(function(id: string, scriptId: string, startsAt: number): ()
			pushed = true
			self:SetState(id, scriptId, startsAt)
		end),
		"Disconnect"
	)
	self.Owner:Add(
		Bus.LiveEvent.CupcakeCollected.OnClientEvent:Connect(function(position: Vector3, amount: number, cash: number): ()
			FeedbackHandler:LaunchCoins(amount, cash, position, COIN_PITCH)
		end),
		"Disconnect"
	)
	self.Owner:Add(RunService.Heartbeat:Connect(function(): ()
		self:Update(workspace:GetServerTimeNow())
	end), "Disconnect")

	-- A push that arrived first is newer than this answer.
	task.spawn(function(): ()
		local ok, id, scriptId, startsAt = pcall(Bus.LiveEvent.Get.Fire, Bus.LiveEvent.Get)
		if ok and not pushed and typeof(id) == "string" and typeof(scriptId) == "string" and typeof(startsAt) == "number" then
			self:SetState(id, scriptId, startsAt)
		end
	end)
end

function LiveEventHandler.SetState(self: LiveEventHandler, id: string, scriptId: string, startsAt: number): ()
	self.State = if id ~= "" and Timeline.GetScript(scriptId)
		then { Id = id, ScriptId = scriptId, StartsAt = startsAt }
		else nil
	self.LineIndex = nil
	self.Speech:Clear()
end

function LiveEventHandler.Update(self: LiveEventHandler, now: number): ()
	local state = self.State
	if not state or Timeline.IsOver(state, now) then
		self.Banner:Hide()
		self.Speech:Clear()
		return
	end
	-- The clock can slide away with the HUD, so the card follows it while the event runs.
	local top = FeedbackHandler:BannerBand()
	self.Banner:Layout(top)
	if now < state.StartsAt then
		self.Banner:ShowCountdown(state.StartsAt - now)
		return
	end

	self.Banner:ShowLive(Timeline.EndsAt(state) - now)
	local index, line = Timeline.LineAt(state.ScriptId, now - state.StartsAt)
	if index == self.LineIndex then
		return
	end
	self.LineIndex = index
	if not line then
		self.Banner:ClearLine()
		self.Speech:Clear()
		return
	end

	local name = speakerName(self.Folder, line.Speaker)
	self.Banner:ShowLine(line.Speaker, name, line.Text)
	self.Speech:Say(line.Speaker, line.Text)
	postToChat(name, line.Text)
end

export type LiveEventHandler = typeof(LiveEventHandler) & {
	State: Timeline.State?,
	-- Index of the line on screen; a change is what triggers the bubble, chat line and banner.
	LineIndex: number?,
	Owner: any,
	Folder: Instance,
	Banner: Banner.Banner,
	Speech: Speech.Speech,
}

return LiveEventHandler :: LiveEventHandler
