--!strict
-- Analytics is best effort and never gates a state transition or a reward.

--[[ Services ]]--
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "TutorialAnalytics" })

--[[ Tables ]]--
local Analytics = {}
local Steps = {
	Started = 1,
	RecipeSelected = 2,
	Mixed = 3,
	CollectedDish = 4,
	OrderTaken = 5,
	Served = 6,
	CleanedTable = 7,
	Completed = 8,
}

--[[ Handling ]]--
function Analytics.Record(player: Player, name: string, stage: string): ()
	if RunService:IsStudio() then
		return
	end
	-- Typed as string? so pcall's second return carries the error message.
	local ok, message = pcall(function(): string?
		local step = Steps[name]
		if step then
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
		end
		if name == "Skipped" then
			AnalyticsService:LogCustomEvent(
				player,
				"TutorialSkipped",
				1,
				{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = stage }
			)
		end
		return nil
	end)
	if not ok then
		Logger:Warn(`Tutorial event {name}: {message}`)
	end
end

return Analytics
