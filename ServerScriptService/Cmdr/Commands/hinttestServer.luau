--!strict
-- TutorialDebug authorization runs in the existing BeforeRun hook before this executor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bus = require(ReplicatedStorage.Shared.Bus)

return function(context: any, mode: string?, target: string?, seconds: number?, rotation: string?): string
	local player = context.Executor
	if not player or player.Parent ~= Players then
		return "Player is no longer in this server."
	end
	local kind = string.lower(mode or "demo")
	if kind ~= "gui" and kind ~= "world" and kind ~= "demo" and kind ~= "hide" then
		return "Use hinttest gui, world, demo, or hide."
	end
	local duration = seconds or 30
	if duration ~= duration or duration < 1 or duration > 300 then
		return "Duration must be between 1 and 300 seconds."
	end
	local angle = rotation or "auto"
	if angle ~= "auto" then
		local value = tonumber(angle)
		if not value or value ~= value or math.abs(value) > 360 then
			return "Rotation must be auto or a finite angle from -360 to 360."
		end
	end
	local path = target or "-"
	if #path > 200 then
		return "Target path is too long."
	end
	Bus.Hints.Debug:FireClient(player, kind, path, duration, angle)
	return if kind == "hide"
		then "Hint preview cleared."
		else `Showing {kind} hint for {duration}s; rotation={angle}. Missing targets are reported on your HUD.`
end
