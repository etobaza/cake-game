--!strict
-- Successful server actions and introduction milestones. A shared observer avoids cycles between
-- gameplay handlers.

local Signal = require(game:GetService("ReplicatedStorage").Shared.Libs.Signal)

return {
	Action = Signal() :: Signal.Signal<Player, string, string>,
	-- A milestone reached for the first time, with the introduction stage it was reached in.
	Milestone = Signal() :: Signal.Signal<Player, string, string>,
}
