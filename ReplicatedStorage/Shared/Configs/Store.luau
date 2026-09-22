--!strict
-- Where each product appears on the Store screen, and on the two reward screens.
--
-- The registry says what a product IS and what buying it does; this file only says where it is shown.
-- The lists are as long as the drawn sections: five currency tiles, two gamepass rows, one featured
-- row. A shorter list leaves the extra tiles hidden rather than showing something made up.

--[[ Tables ]]--
local Store = {
	-- Ids from Configs/Registries/Products, in the order the screen draws them.
	Currency = { "cash_1", "cash_2", "cash_3", "cash_4", "cash_5" },
	Gamepasses = { "pass_vip", "pass_display" },
	Featured = { "starter_pack" },

	-- The Robux buttons that live on the reward screens instead of in the store.
	Skips = {
		Daily = "skip_daily",
		Playtime = "skip_playtime",
	},

	-- Shown in the gamepass header as "n/total Owned".
	OwnedTotal = 2,
}

return Store
