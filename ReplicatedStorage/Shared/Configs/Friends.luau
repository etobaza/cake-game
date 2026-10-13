--!strict
-- Active server friends boost gameplay earnings. Invitations never grant a reward by themselves.

local Friends = {
	PercentPerFriend = 10,
	MaxPercent = 50,
	RefreshSeconds = 120,
	RetrySeconds = 30,
	TickSeconds = 1,
	MaxConcurrentChecks = 4,
	CheckTimeoutSeconds = 12,
	-- Codes use the existing Gameplay analytics reason, but are not earned bakery income.
	ExcludedGameplayItems = { Code = true } :: { [string]: boolean },
	Invite = {
		CooldownSeconds = 2,
		CheckTimeoutSeconds = 12,
		PromptTimeoutSeconds = 120,
		StudioMessage = "Invites could not open here. Try the published game in Roblox.",
		UnavailableMessage = "Invites are unavailable for this account or device.",
		ErrorMessage = "Invites could not open. Please try again shortly.",
		Icon = "rbxassetid://72029296612385",
		IconSize = 28,
		IconGap = 6,
		HitPadding = 4,
		EdgePadding = 8,
		RowHeight = 44,
		TextHeight = 28,
		TextWidth = 184,
		TextSize = 20,
		MinTextSize = 14,
		-- The Currency group's unscaled desktop width (HudLayout); wider groups scale the row up.
		DesktopCurrencyWidth = 250,
	},
}

function Friends.GetPercent(count: number): number
	return math.clamp(math.floor(count) * Friends.PercentPerFriend, 0, Friends.MaxPercent)
end

return Friends
