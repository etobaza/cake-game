--!strict
-- Small repeatable Robux offers, sold in the Store and pushed at the moment they matter:
--   * DoubleShift: pays a finished shift's profit once more, also from a button on the day report;
--   * RescueDish: a dish that burned in the oven comes back ready to serve;
--   * KeepGuest: every waiting guest's patience fills up again.
--
-- A purchase works at once when its moment is there; otherwise it waits as a charge
-- (Cloud.OfferCharges) and is spent automatically the next time (OfferHandler).
--
-- The server also opens the Roblox prompt on its own at those moments, so it is limited hard: never
-- during the tutorial or the first days, at most one automatic prompt per GlobalCooldown, and each
-- offer has its own cooldown on top.
--
-- Rescue Dish and Keep Guests take over the HUD's 2x Cash button too: at once while they apply (a
-- burnt dish, a guest about to walk out), and otherwise taking turns with it every Hud.SwapEvery
-- seconds. Their `Hud` rows hold that face.
--
-- Every offer is a Registries/Products row (grant = the offer name, `offer = true`). Rows with
-- productId 0 are not on sale and are never prompted.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)

--[[ Types ]]--
export type OfferName = "DoubleShift" | "RescueDish" | "KeepGuest"

export type Offer = {
	-- Registries/Products entry the offer sells.
	Product: string,
	-- Seconds between automatic prompts of this offer for one player.
	Cooldown: number,
}

-- How an offer looks while it stands in for the HUD's 2x Cash button.
export type HudFace = {
	Icon: string,
	Text: string,
}

--[[ Tables ]]--
local Offers = {
	-- No automatic prompt before this saved day: the first days belong to learning the bakery.
	MinDay = 2,
	-- Seconds between any two automatic prompts for one player, whichever offers they are.
	GlobalCooldown = 120,

	-- The HUD's 2x Cash button: which offers may take it over (an applying one first, else in turn),
	-- how often the client checks, and the rotation: the face changes every SwapEvery seconds,
	-- 2x Cash and the offers of Order taking turns (2x, RescueDish, 2x, KeepGuest, ...).
	Hud = {
		Order = { "RescueDish", "KeepGuest" },
		CheckInterval = 0.5,
		SwapEvery = 15,
	},
	-- Guest states whose patience can run out (GuestState's `expire`).
	WaitingStates = {
		Queued = true,
		Arriving = true,
		Choosing = true,
		Waiting = true,
		Shopping = true,
	} :: { [string]: boolean },

	DoubleShift = {
		Product = "double_shift",
		Cooldown = 0,
		-- The report opens this many shifts apart with the prompt already up; on the others only the
		-- button is shown.
		PromptEveryShifts = 3,
		-- Seconds after the report opens before that prompt, so the profit is read first.
		PromptDelay = 1.5,
		-- Shifts that earned less are not offered: doubling a few coins is not worth the Robux.
		MinCoins = 500,
		Button = {
			-- Authored button cloned for its look: the report's Next Menu button.
			Template = { "Header", "Buttons", "Menu" },
			Name = "DoubleShift",
			-- Inside the Daily Profits row, in the gap between its caption and the amount: the panel
			-- fills the screen's height on desktops, so anything on or past its edge is cut off.
			Parent = { "DailyProfit" },
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.36, 0.8),
			Text = "Double profit",
			Color = Color3.fromRGB(96, 196, 84),
			StrokeColor = Color3.fromRGB(40, 110, 40),
			-- Seconds per breath of the idle pulse, and how much the button grows at its top.
			PulsePeriod = 1.4,
			PulseScale = 0.05,
		},
	},

	RescueDish = {
		Product = "rescue_dish",
		Cooldown = 180,
		Hud = {
			-- A baguette rising out of smoke with a green restore badge (assets/ui/rescue-dish.png).
			Icon = "rbxassetid://78412774375162",
			Text = "Rescue dish",
		} :: HudFace,
	},

	KeepGuest = {
		Product = "keep_guest",
		Cooldown = 240,
		-- A waiting guest with less than this share of patience left triggers the offer.
		Threshold = 0.3,
		-- Seconds between patience checks.
		CheckInterval = 1,
		Hud = {
			-- A gold hourglass with a heart and plus badge (assets/ui/keep-guests.png).
			Icon = "rbxassetid://134349148673729",
			Text = "Keep guests",
		} :: HudFace,
	},
}

--[[ Handling ]]--
--- Whether automatic prompts may open: no Roblox prompt interrupts the tutorial or the first days.
function Offers.IsUnlocked(cloud: any): boolean
	return Offers.IsPastTutorial(cloud) and (cloud.Day or 0) >= Offers.MinDay
end

--- Whether the tutorial is over (the HUD face ignores it: it never prompts by itself).
function Offers.IsPastTutorial(cloud: any): boolean
	return cloud ~= nil and not TutorialPolicy.IsActive(cloud)
end

--- Share of patience a guest has left, or nil for a guest whose patience is not running.
function Offers.PatienceLeft(customer: any, now: number): number?
	if customer.TutorialProtected or not Offers.WaitingStates[customer.State] or customer.PatienceEndsAt <= 0 then
		return nil
	end
	local patience = customer.Patience or 0
	if patience <= 0 then
		return nil
	end
	return (customer.PatienceEndsAt - now) / patience
end

--- The HUD face and product of an offer that can wear the 2x Cash button; nil for any other name.
function Offers.GetHud(offer: string): (HudFace?, string?)
	local spec = if offer == "RescueDish" then Offers.RescueDish elseif offer == "KeepGuest" then Offers.KeepGuest else nil
	if not spec then
		return nil, nil
	end
	return spec.Hud, spec.Product
end

--- Whether Rescue Dish or Keep Guests applies right now, read from Session data (the server's or the
--- client's mirror): a station holds a burnt dish, or a guest has less than Threshold patience left.
function Offers.Applies(offer: string, session: any, now: number): boolean
	if not session then
		return false
	end
	if offer == "RescueDish" then
		for _, station in session.Stations or {} do
			if station.State == "Burnt" then
				return true
			end
		end
		return false
	end
	if offer == "KeepGuest" then
		for _, customer in session.Customers or {} do
			local left = Offers.PatienceLeft(customer, now)
			if left and left > 0 and left < Offers.KeepGuest.Threshold then
				return true
			end
		end
	end
	return false
end

--- Whether the report may offer Double Profit: the evening of the recorded shift, not bought yet, and
--- a profit worth doubling. `record` is Cloud.DoubleShift, `day` is Session.Day; both sides read it.
function Offers.CanDoubleShift(record: any, day: any): boolean
	return record ~= nil
		and day ~= nil
		and day.Phase == "Summary"
		and record.Day == day.Number
		and record.Doubled ~= true
		and (record.Coins or 0) >= Offers.DoubleShift.MinCoins
end

return Offers
