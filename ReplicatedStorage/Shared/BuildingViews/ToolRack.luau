--!strict
-- Prompt view of a tool rack: take the tool it holds, put it back when done.
-- One view for every rack — which tool it gives is the ToolId of the building kind.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local BuildingsConfig = require(_Shared.Configs.Buildings)
local Bus = require(_Shared.Bus)
local CarryPolicy = require(_Shared.CarryPolicy)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local ToolRack = {}

--[[ Handling ]]--
function ToolRack.Describe(context: Types.Context): Types.PromptState
	local kind = BuildingsConfig.Kinds[context.Kind]
	local held = context.Held()
	local holding = held and held.Kind == "Tool" and held.Id == kind.ToolId

	if holding then
		return {
			Label = kind.Label,
			Action = "Put back",
			Fire = function()
				Bus.Cafe.ReturnTool:Fire(context.PropId)
			end,
		}
	end

	-- Dispenser ingredients return automatically when the tool pickup succeeds.
	if held and not CarryPolicy.CanReplace(held) then
		return { Label = "Hands full" }
	end

	return {
		Label = kind.Label,
		Action = "Take",
		Fire = function()
			Bus.Cafe.TakeTool:Fire(context.PropId)
		end,
	}
end

return ToolRack
