--!strict
-- Interface texts: refusal codes from the server and day phase labels.
-- Everything the player sees is written here and in English only.

--[[ Tables ]]--
local UIText = {
	-- Every code the server sends in Progress.ActionFailed.
	Failures = {
		-- Day and menu
		not_prep_phase = "Only during prep time",
		not_summary_phase = "Plan tomorrow's menu after closing",
		menu_too_small = "Pick at least 3 recipes",
		menu_too_large = "Pick no more than 5 recipes",
		menu_not_ready = "Set today's menu first",
		recipe_locked = "Recipe not unlocked yet",
		not_on_menu = "That's not on today's menu",

		-- Upgrades
		unknown_upgrade = "No such upgrade",
		level_too_low = "Your level is too low",
		max_level = "Already maxed out",
		not_enough_coins = "Not enough coins",
		needs_parent = "Buy the upgrade it grows from first",
		no_assistant = "You haven't hired an assistant",

		-- Kitchen
		station_missing = "You don't have that station",
		station_busy = "Station is busy",
		wrong_station = "Wrong station for this",
		no_fuel = "The oven is out of firewood",
		fuel_full = "The oven is already full",
		need_firewood = "Fetch a log from the woodpile first",
		missing_ingredients = "Missing ingredients",
		select_recipe = "Choose a recipe at the mixer first",
		ingredient_not_needed = "That ingredient is not needed for this recipe",
		ingredient_complete = "The mixer already has enough of that ingredient",
		mixer_has_ingredients = "Take the ingredients out of the mixer before changing recipe",
		too_far = "Move closer to the station",
		out_of_stock = "That ingredient is out of stock",
		nothing_to_load = "Nothing in your hands to load",
		need_frozen_mix = "Bring a frozen dessert mixture from the mixer first",
		wrong_frozen_mix = "Wrong mixture: the freezer needs a frozen dessert",
		nothing_to_cancel = "Nothing to cancel",
		wrong_dispenser = "That item cannot be returned here",
		not_ready = "Not ready yet",

		-- Hands, display, customers
		hands_full = "Your hands are full",
		nothing_to_place = "No finished dish in your hands",
		display_empty = "The window displays are empty!",
		slot_taken = "That display slot is taken",
		nothing_to_serve = "No dish in your hands",
		bake_before_serving = "Bake it in the oven before serving",
		wrong_dish = "The guest ordered something else",
		need_broom = "Pick up the broom first",
		put_broom_back = "Put the tool back on its stand",

		-- Rewards
		unknown_code = "No such code",
		code_used = "You have already used that code",
		daily_not_ready = "Come back tomorrow for the next day",
		daily_done = "The whole streak is claimed",
		playtime_not_ready = "Not played long enough for that one",
		playtime_claimed = "Already claimed",

		-- Garden
		already_tended = "Already tended today",
		need_watering_can = "Fetch the watering can first",
		cart_full = "Collect the kitchen deliveries first",
		cart_produce_only = "The cart carries ingredients",
		nothing_to_harvest = "Nothing to harvest yet",
	},

	-- Signage words, Lemon Cake style: the bakery is closed while prepping and closing after the
	-- shift; a running shift shows the countdown instead of a word.
	Phases = {
		Prep = "Open Bakery",
		Shift = "Shift",
		Summary = "Closing",
	},
}

--[[ Handling ]]--
-- Readable refusal reason; an unknown code is shown as is so the signal is not lost.
function UIText.GetFailure(code: string): string
	return UIText.Failures[code] or code
end

function UIText.GetPhase(phase: string): string
	return UIText.Phases[phase] or phase
end

return UIText
