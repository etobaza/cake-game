--!strict
-- Successful server actions only. A shared observer avoids cycles between gameplay handlers.

local Signal = require(game:GetService("ReplicatedStorage").Shared.Libs.Signal)

return {
	Action = Signal() :: Signal.Signal<Player, string, string>,
}
