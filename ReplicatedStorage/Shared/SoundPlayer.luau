--!strict
-- Builds configured Sound instances. A world parent (part, attachment) gives positional audio that
-- replicates when created by the server; without a parent the client plays it unpositioned.

--[[ Services ]]--
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

--[[ Modules ]]--
local Config = require(script.Parent.Configs.Sounds)

--[[ Tables ]]--
local SoundPlayer = {}

--[[ Handling ]]--
--- A stopped sound owned by `parent`; the caller controls playback.
function SoundPlayer.Create(name: Config.SoundName, parent: Instance): Sound
	local definition = Config.Sounds[name]
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = definition.Id
	sound.Volume = definition.Volume
	sound.Looped = definition.Looped == true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = definition.MinDistance or Config.MinDistance
	sound.RollOffMaxDistance = definition.MaxDistance or Config.MaxDistance
	sound.Parent = parent
	return sound
end

--- Plays once and removes itself. Destroying the returned sound (or its parent) stops it early.
--- `playbackSpeed` shifts the pitch, so repeated feedback (coins, streaks) can climb.
function SoundPlayer.Play(name: Config.SoundName, parent: Instance?, playbackSpeed: number?): Sound
	local sound = SoundPlayer.Create(name, parent or SoundService)
	if playbackSpeed then
		sound.PlaybackSpeed = playbackSpeed
	end
	sound.Ended:Once(function(): ()
		sound:Destroy()
	end)
	Debris:AddItem(sound, Config.Lifetime)
	sound:Play()
	return sound
end

return SoundPlayer
