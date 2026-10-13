--!strict
-- Replicate presentation timing from the station proxy; this adds no gameplay timer or saved field.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataHandler = require(game:GetService("ServerScriptService").Handlers.DataHandler)
local CookingMotion = require(ReplicatedStorage.Shared.Configs.CookingMotion)

local STATION = CookingMotion.Station
-- Station proxy timestamps and the motion attribute each one is replicated as.
local TIMING_FIELDS = {
	{ Field = "PhaseStartedAt", Attribute = STATION.PhaseStartedAt },
	{ Field = "ReadyAt", Attribute = STATION.ReadyAt },
	{ Field = "BurnAt", Attribute = STATION.BurnAt },
	{ Field = "HeatPausedAt", Attribute = STATION.HeatPausedAt },
}

local CookingMetadata = {}

function CookingMetadata.Apply(target: Instance, state: any, player: Player): ()
	target:SetAttribute(STATION.StationState, state.State or "Idle")
	for _, timing in TIMING_FIELDS do
		target:SetAttribute(timing.Attribute, state[timing.Field] or 0)
	end
	local data = DataHandler:GetData(player)
	local day = data and data.Session.Day
	target:SetAttribute(STATION.PausedAt, if day and day.Phase == "Summary" then day.SummaryStartedAt else 0)
end

return CookingMetadata
