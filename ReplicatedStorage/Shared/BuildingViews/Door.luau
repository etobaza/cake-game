--!strict
-- Entrance prompt: opens the prepared bakery, closes an active shift, and disappears while the
-- evening Summary owns the player. The server re-checks range, ownership and phase.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local Door = {}

--[[ Handling ]]--
function Door.Describe(context: Types.Context): Types.PromptState
	local day = context.Session("Day")
	local phase = day and day.Phase
	if phase == "Prep" then
		return {
			Label = "Closed",
			Action = "Open Restaurant",
			Fire = function()
				Bus.Day.ToggleDoor:Fire(context.PropId)
			end,
		}
	end

	if phase == "Shift" then
		return {
			Label = "Open",
			Action = "Close Restaurant",
			Fire = function()
				Bus.Day.ToggleDoor:Fire(context.PropId)
			end,
		}
	end

	return { Label = "Closed" }
end

return Door
