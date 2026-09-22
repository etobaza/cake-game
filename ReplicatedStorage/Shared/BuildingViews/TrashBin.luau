--!strict
-- Prompt view of the trash bin: throws away whatever the player carries.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Bus = require(_Shared.Bus)
local Types = require(script.Parent.Types)

--[[ Tables ]]--
local TrashBin = {}

--[[ Handling ]]--
function TrashBin.Describe(context: Types.Context): Types.PromptState
	local held = context.Held()
	if not held then
		-- InteractHandler disables prompts with no Action. Keep the authored bin visible even before
		-- the player picks up a wrong ingredient, so its purpose is discoverable in the kitchen.
		return {
			Label = BuildingsConfig.Kinds[context.Kind].Label,
			Action = "Empty",
		}
	end

	if held.Kind == "Tool" then
		return { Label = "Return tool" }
	end

	return {
		Label = context.ItemName(held),
		Action = "Throw away",
		Fire = function()
			Bus.Kitchen.Trash:Fire(context.PropId)
		end,
	}
end

return TrashBin
