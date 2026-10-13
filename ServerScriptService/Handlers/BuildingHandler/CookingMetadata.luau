--!strict
-- Replicate presentation timing from the station proxy; this adds no gameplay timer or saved field.
local DataHandler = require(game:GetService("ServerScriptService").Handlers.DataHandler)

local CookingMetadata = {}

function CookingMetadata.Apply(target: Instance, state: any, player: Player): ()
	target:SetAttribute("StationState", state.State or "Idle")
	for _, field in { "PhaseStartedAt", "ReadyAt", "BurnAt", "HeatPausedAt" } do
		target:SetAttribute(field, state[field] or 0)
	end
	local data = DataHandler:GetData(player)
	local day = data and data.Session.Day
	target:SetAttribute("PausedAt", if day and day.Phase == "Summary" then day.SummaryStartedAt else 0)
end

return CookingMetadata
