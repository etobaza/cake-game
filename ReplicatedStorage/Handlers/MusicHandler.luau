--!strict
-- Background music on the local client: Configs/Music's tracks play one after another and loop.
-- Each track fades in over its first FadeSeconds and out over its last, so consecutive tracks never
-- overlap and never cut. A topbar toggle mutes the music group; the choice is saved in
-- Cloud.Settings.MusicMuted (SettingsHandler) and the label follows the replicated value.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

--[[ References ]]--
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.Music)
local DataClient = require(_Handlers.DataHandlerClient)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local TopbarHandler = require(_Handlers.TopbarHandler)

--[[ Constants ]]--
local ACTION_KEY = "Music"
local LABEL_ON = "Music: On"
local LABEL_OFF = "Music: Off"
local CAPTION = "Turn the music on or off"
-- After Daily Rewards (1), Codes (2) and the group reward (3).
local ORDER = 4

--[[ Tables ]]--
local MusicHandler = {
	dependencies = { "DataClient", "TopbarHandler" },
}

--[[ Private Functions ]]--
-- Volume at the sound's current position: ramps up after the start and down before the end.
local function fadedVolume(sound: Sound): number
	local length = sound.TimeLength
	if length <= 0 then
		return 0
	end
	local fade = math.min(Config.FadeSeconds, length / 2)
	local position = sound.TimePosition
	local fadeIn = math.clamp(position / fade, 0, 1)
	local fadeOut = math.clamp((length - position) / fade, 0, 1)
	return Config.Volume * math.min(fadeIn, fadeOut)
end

--[[ Handling ]]--
function MusicHandler.OnStart(self: MusicHandler): ()
	self.Janitor = Janitor.new()
	self.Sounds = {}
	self.Failed = {}
	self.Index = 0
	self.StartedAt = 0

	local group = Instance.new("SoundGroup")
	group.Name = Config.GroupName
	group.Parent = SoundService
	self.Janitor:Add(group, "Destroy")

	-- Muting silences the group and lets the playlist run on, so unmuting resumes mid-track.
	local toggle = TopbarHandler:CreateAction(ACTION_KEY, LABEL_ON, CAPTION, ORDER, function(): ()
		Bus.Player.SetMusicMuted:Fire(not self:IsMuted())
	end)
	local function applyMuted(): ()
		local muted = self:IsMuted()
		group.Volume = if muted then 0 else 1
		toggle:setLabel(if muted then LABEL_OFF else LABEL_ON)
	end
	DataClient:WaitForData()
	applyMuted()
	self.Janitor:Add(DataClient:SubscribeToPath({ "Settings", "MusicMuted" }, applyMuted, "Cloud"), "Disconnect")

	for _, track in Config.Tracks do
		local sound = Instance.new("Sound")
		sound.Name = track.Name
		sound.SoundId = track.Id
		sound.Volume = 0
		sound.SoundGroup = group
		sound.Parent = group
		self.Janitor:Add(
			sound.Ended:Connect(function(): ()
				self:Next()
			end),
			"Disconnect"
		)
		self.Sounds[#self.Sounds + 1] = sound
	end
	if #self.Sounds == 0 then
		return
	end

	self.Janitor:Add(
		RunService.Heartbeat:Connect(function(): ()
			self:Step()
		end),
		"Disconnect"
	)
	self:Next()
end

-- Starts the following track from its beginning; the previous one has already faded out. Tracks
-- that already failed to load are skipped, so a missing asset does not cost a timeout every loop.
function MusicHandler.Next(self: MusicHandler): ()
	local previous = self.Sounds[self.Index]
	if previous then
		previous:Stop()
	end
	for _ = 1, #self.Sounds do
		self.Index = self.Index % #self.Sounds + 1
		if not self.Failed[self.Sounds[self.Index]] then
			break
		end
	end
	if self.Failed[self.Sounds[self.Index]] then
		-- Every track failed; stay silent instead of retrying.
		self.Index = 0
		return
	end
	self.StartedAt = os.clock()
	local sound = self.Sounds[self.Index]
	sound.Volume = 0
	sound.TimePosition = 0
	sound:Play()
end

function MusicHandler.Step(self: MusicHandler): ()
	local sound = self.Sounds[self.Index]
	if not sound then
		return
	end
	-- A track that never loads (moderated, network failure) would otherwise silence the playlist.
	if not sound.IsLoaded then
		if os.clock() - self.StartedAt > Config.LoadTimeoutSeconds then
			warn(`[MusicHandler] {sound.Name} did not load in {Config.LoadTimeoutSeconds}s; skipping it for this session`)
			self.Failed[sound] = true
			self:Next()
		end
		return
	end
	sound.Volume = fadedVolume(sound)
end

function MusicHandler.IsMuted(_self: MusicHandler): boolean
	return DataClient:GetData({ "Settings", "MusicMuted" }, "Cloud") == true
end

function MusicHandler.Destroy(self: MusicHandler): ()
	local janitor = self.Janitor
	self.Janitor = nil
	if janitor then
		janitor:Destroy()
	end
end

export type MusicHandler = typeof(MusicHandler) & {
	Janitor: any,
	Sounds: { Sound },
	-- Tracks that timed out while loading this session.
	Failed: { [Sound]: true? },
	Index: number,
	StartedAt: number,
}

return MusicHandler :: MusicHandler
