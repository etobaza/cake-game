--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage.Shared.Registry)

-- "limited": an item sold through the shared limited slot (Configs/Limited), never prompted itself;
-- its row carries the name and bonus, and LimitedHandler adds it to Cloud.Passes once owned.
export type ProductType = "gamepass" | "permanent_devproduct" | "devproduct" | "limited"

-- What buying the thing actually does.
-- Cash: a one-off pile of coins. Stat: a permanent bonus on top of the upgrade for that stat, for as
-- long as the pass is owned. CashMultiplier: every coin the player earns, times this.
-- SkipDaily / SkipDailyAll / SkipPlaytime: moves a reward track forward; the reward handler owns those.
-- Limited: whichever limited item is on sale; LimitedHandler resolves and grants it.
-- Worker: a pass whose effect is a bakery worker (Configs/Workers); recording ownership is the grant.
-- CashBoost: adds time to the 2x coin boost (Configs/CashBoost); CashBoostHandler owns it.
export type GrantKind =
	"Cash"
	| "Stat"
	| "CashMultiplier"
	| "SkipDaily"
	| "SkipDailyAll"
	| "SkipPlaytime"
	| "Limited"
	| "Worker"
	| "CashBoost"

export type ProductMeta = {
	-- What the store shows. `value` is the big number on a currency tile.
	name: string,
	blurb: string?,
	value: string?,
	grant: GrantKind,
	amount: number,
	-- Only for grant = "Stat": which BaseStats key the bonus lands on.
	stat: string?,
	-- Tile art; tiles without one keep their authored image.
	icon: string?,
	-- Sold only through LimitedHandler, which checks the shared stock first (Configs/Limited).
	limited: boolean?,
}

-- The authored shape; Registry.Build stamps `id` onto every entry.
type ProductDefinition = {
	-- 0 until the real id is pasted in from the Creator Dashboard. Everything reads as "not for sale"
	-- until then: the store shows the row and refuses the press instead of prompting for nothing.
	productId: number,
	productType: ProductType,
	giftId: number?, -- productId of the gift variant (if this product can be gifted)
	meta: ProductMeta?,
}
export type ProductEntry = ProductDefinition & { id: string }

local list: { [string]: ProductDefinition } = {
	--[[ Currency packages ]]--
	-- Sized against a shift (6 000-8 000 coins early on) for 49/99/249/499/999 Robux on the Creator
	-- Dashboard, so each bigger pack pays clearly more coins per Robux (153 up to 275).
	cash_1 = {
		productId = 3715828865,
		productType = "devproduct",
		meta = { name = "Cash", value = "7,500$", grant = "Cash", amount = 7500, icon = "rbxassetid://96216232687018" },
	},
	cash_2 = {
		productId = 3715828878,
		productType = "devproduct",
		meta = { name = "Cash", value = "17,500$", grant = "Cash", amount = 17500, icon = "rbxassetid://114454707057271" },
	},
	cash_3 = {
		productId = 3715828888,
		productType = "devproduct",
		meta = { name = "Cash", value = "50,000$", grant = "Cash", amount = 50000, icon = "rbxassetid://71273978435843" },
	},
	cash_4 = {
		productId = 3715828897,
		productType = "devproduct",
		meta = { name = "Cash", value = "120,000$", grant = "Cash", amount = 120000, icon = "rbxassetid://127494963095045" },
	},
	cash_5 = {
		productId = 3715828907,
		productType = "devproduct",
		meta = { name = "Cash", value = "275,000$", grant = "Cash", amount = 275000, icon = "rbxassetid://110097182380053" },
	},

	--[[ Gamepasses ]]--
	-- Both plug into systems that already exist: the multiplier into every coin the player earns,
	-- the stat bonus into the same sum the upgrades feed. VIP is 199 Robux, Bigger Window 149.
	pass_vip = {
		productId = 2002796698,
		productType = "gamepass",
		meta = {
			icon = "rbxassetid://82564416622684",
			name = "VIP",
			blurb = "Every sale pays 25% more, forever.",
			grant = "CashMultiplier",
			amount = 1.25,
		},
	},
	pass_display = {
		productId = 2001338949,
		productType = "gamepass",
		meta = {
			icon = "rbxassetid://88029545591527",
			name = "Bigger Window",
			blurb = "Two more display slots on top of your upgrades.",
			grant = "Stat",
			stat = "DisplaySlots",
			amount = 2,
		},
	},

	-- Worker passes (Configs/Workers). The Helper is a Stat pass on the assistant slot, so it unlocks
	-- the assistant without the upgrade; owning it also doubles the assistant's pace and dresses it.
	-- 299 and 149 Robux.
	pass_helper = {
		productId = 2046249065,
		productType = "gamepass",
		meta = {
			icon = "rbxassetid://76365950185800",
			name = "Hire a Helper",
			blurb = "A chef works your café: carries pastries, serves coffee, clears tables. Twice as fast.",
			grant = "Stat",
			stat = "AssistantSlots",
			amount = 1,
		},
	},
	pass_cleaner = {
		productId = 2047982350,
		productType = "gamepass",
		meta = {
			icon = "rbxassetid://125288289282098",
			name = "Auto-Cleaner",
			blurb = "A cleaner mops spills and wipes dirty tables for you.",
			grant = "Worker",
			amount = 1,
		},
	},

	--[[ Boosts ]]--
	-- Repeatable, 15 minutes of doubled gameplay coins each (Configs/CashBoost).
	boost_cash_2x = {
		productId = 3720887751,
		productType = "devproduct",
		meta = {
			icon = "rbxassetid://109504819496800",
			name = "2x Cash",
			blurb = "Every sale pays double for 15 minutes.",
			grant = "CashBoost",
			amount = 15 * 60,
		},
	},

	--[[ Featured ]]--
	-- 99 Robux, once per player: about twice the coins per Robux of the biggest pack.
	starter_pack = {
		productId = 3715828914,
		productType = "permanent_devproduct",
		meta = {
			name = "Starter Pack",
			blurb = "Contains 50,000$ to get the bakery going.",
			grant = "Cash",
			amount = 50000,
		},
	},

	--[[ Limited ]]--
	-- One repeatable developer product for every drop (500 Robux). LimitedHandler decides which item a
	-- receipt buys: the drop the buyer was prompted for, else the one on sale (Configs/Limited).
	limited_slot = {
		productId = 3720767346,
		productType = "devproduct",
		meta = { name = "Limited Item", grant = "Limited", amount = 0, limited = true },
	},
	-- The items themselves. Never prompted; owning one adds its row to Cloud.Passes, so the bonus
	-- lands like a pass's. The golden oven skin is LimitedHandler's.
	limited_golden_oven = {
		productId = 0,
		productType = "limited",
		meta = {
			name = "Golden Oven",
			blurb = "Your ovens turn gold, and food takes 30 seconds longer to burn.",
			grant = "Stat",
			stat = "BurnTimeMult",
			amount = 1,
		},
	},

	--[[ Reward track skips ]]--
	-- 29, 149 and 49 Robux: one day is a small top-up, the whole streak (up to 38 500$) and the whole
	-- playtime track (up to 12 200$) pay about as well per Robux as the mid-size cash packs.
	skip_daily = {
		productId = 3715828918,
		productType = "devproduct",
		meta = { name = "Skip 1 Day", grant = "SkipDaily", amount = 1 },
	},
	skip_daily_all = {
		productId = 3718628937,
		productType = "devproduct",
		meta = { name = "Skip All Days", grant = "SkipDailyAll", amount = 0 },
	},
	skip_playtime = {
		productId = 3715828921,
		productType = "devproduct",
		meta = { name = "Skip All", grant = "SkipPlaytime", amount = 0 },
	},
}

type ProductsMethods = {
	GetByProductId: (self: ProductsRegistry, productId: number) -> ProductEntry?,
	GetByGiftId: (self: ProductsRegistry, giftId: number) -> ProductEntry?,
	GetCashMultiplier: (self: ProductsRegistry, owned: { string }?) -> number,
	GetStatBonus: (self: ProductsRegistry, owned: { string }?, statKey: string) -> number,
}
export type ProductsRegistry = Registry.Registry<ProductEntry> & ProductsMethods

local methods: ProductsMethods = {
	-- Find product by productId (for ProcessReceipt lookup)
	GetByProductId = function(self: ProductsRegistry, productId: number): ProductEntry?
		return self:Query()
			:Where(function(e: ProductEntry)
				return e.productId == productId
			end)
			:FirstOrDefault()
	end,

	-- Find product by giftId (for gift purchase lookup)
	GetByGiftId = function(self: ProductsRegistry, giftId: number): ProductEntry?
		return self:Query()
			:Where(function(e: ProductEntry)
				return e.giftId == giftId
			end)
			:FirstOrDefault()
	end,

	-- Coin multiplier from the passes a player owns. They stack by multiplying, so two 1.25 passes
	-- are 1.5625 and not 1.5 -- there is only one such pass today, and the rule has to say something.
	GetCashMultiplier = function(self: ProductsRegistry, owned: { string }?): number
		local multiplier = 1

		for _, entryId in (owned or {}) :: { string } do
			local entry = self:Get(entryId)
			local meta = entry and entry.meta
			if meta and meta.grant == "CashMultiplier" then
				multiplier *= meta.amount
			end
		end

		return multiplier
	end,

	-- Flat bonus the owned passes add to one BaseStats key, on top of the upgrades.
	GetStatBonus = function(self: ProductsRegistry, owned: { string }?, statKey: string): number
		local bonus = 0

		for _, entryId in (owned or {}) :: { string } do
			local entry = self:Get(entryId)
			local meta = entry and entry.meta
			if meta and meta.grant == "Stat" and meta.stat == statKey then
				bonus += meta.amount
			end
		end

		return bonus
	end,
}

local ProductsRegistry: ProductsRegistry = Registry.Build("Products", list, methods)

return ProductsRegistry
