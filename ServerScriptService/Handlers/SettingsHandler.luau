--!strict
-- Player preferences the client toggles (the topbar music switch). They only change presentation on
-- that player's own client, so the server checks the type and saves the value in Cloud.Settings.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local DataHandler = require(ServerScriptService.Handlers.DataHandler)

--[[ Tables ]]--
local SettingsHandler = {
	dependencies = { "DataHandler" },
	priority = 0,
}

--[[ Handling ]]--
function SettingsHandler.OnStart(self: SettingsHandler): ()
	Bus.Player.SetMusicMuted.OnServerEvent:Connect(function(player: Player, muted: any)
		if typeof(muted) ~= "boolean" then
			return
		end

		self:SetMusicMuted(player, muted)
	end)
end

function SettingsHandler.SetMusicMuted(_self: SettingsHandler, player: Player, muted: boolean): ()
	local data = DataHandler:GetData(player)
	if not data or data.Cloud.Settings.MusicMuted == muted then
		return
	end

	data.Cloud.Settings.MusicMuted = muted
end

export type SettingsHandler = typeof(SettingsHandler)

return SettingsHandler
