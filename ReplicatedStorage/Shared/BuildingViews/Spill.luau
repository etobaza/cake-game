--!strict
-- Prompt view of a floor spill: mop it, but only while the broom is in the player's hands.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local BuildingsConfig = require(_Shared.Configs.Buildings)
local Bus = require(_Shared.Bus)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local Spill = {}

--[[ Handling ]]--
function Spill.Describe(context: Types.Context): Types.PromptState
	local kind = BuildingsConfig.Kinds.Spill
	local broomId = BuildingsConfig.Kinds.Broom.ToolId
	local held = context.Held()
	if not held or held.Kind ~= "Tool" or held.Id ~= broomId then
		return { Label = "Needs broom" }
	end

	return {
		Label = kind.Label,
		Action = "Sweep",
		Fire = function()
			Bus.Cafe.CleanSpill:Fire(context.PropId)
		end,
	}
end

return Spill
