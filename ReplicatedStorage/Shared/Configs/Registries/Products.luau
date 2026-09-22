--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage.Shared.Registry)

export type ProductType = "gamepass" | "permanent_devproduct" | "devproduct"

-- What buying the thing actually does.
-- Cash: a one-off pile of coins. Stat: a permanent bonus on top of the upgrade for that stat, for as
-- long as the pass is owned. CashMultiplier: every coin the player earns, times this.
-- SkipDaily / SkipPlaytime: moves a reward track forward; the reward handler owns those.
export type GrantKind = "Cash" | "Stat" | "CashMultiplier" | "SkipDaily" | "SkipPlaytime"

export type ProductMeta = {
	-- What the store shows. `value` is the big number on a currency tile.
	name: string,
	blurb: string?,
	value: string?,
	grant: GrantKind,
	amount: number,
	-- Only for grant = "Stat": which BaseStats key the bonus lands on.
	stat: string?,
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

-- Gamepasses are priced through a different InfoType; anything else reads as a dev product.
local function GetInfoType(productType: ProductType): Enum.InfoType
	if productType == "gamepass" then
		return Enum.InfoType.GamePass
	end

	return Enum.InfoType.Product
end

local list: { [string]: ProductDefinition } = {
	--[[ Currency packages ]]--
	cash_1 = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Cash", value = "350$", grant = "Cash", amount = 350 },
	},
	cash_2 = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Cash", value = "1 000$", grant = "Cash", amount = 1000 },
	},
	cash_3 = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Cash", value = "3 000$", grant = "Cash", amount = 3000 },
	},
	cash_4 = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Cash", value = "8 000$", grant = "Cash", amount = 8000 },
	},
	cash_5 = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Cash", value = "25 000$", grant = "Cash", amount = 25000 },
	},

	--[[ Gamepasses ]]--
	-- Both plug into systems that already exist: the multiplier into every coin the player earns,
	-- the stat bonus into the same sum the upgrades feed.
	pass_vip = {
		productId = 0,
		productType = "gamepass",
		meta = {
			name = "VIP",
			blurb = "Every sale pays 25% more, forever.",
			grant = "CashMultiplier",
			amount = 1.25,
		},
	},
	pass_display = {
		productId = 0,
		productType = "gamepass",
		meta = {
			name = "Bigger Window",
			blurb = "Two more display slots on top of your upgrades.",
			grant = "Stat",
			stat = "DisplaySlots",
			amount = 2,
		},
	},

	--[[ Featured ]]--
	starter_pack = {
		productId = 0,
		productType = "permanent_devproduct",
		meta = {
			name = "Starter Pack",
			blurb = "Contains $500 cash to get the bakery going.",
			grant = "Cash",
			amount = 500,
		},
	},

	--[[ Reward track skips ]]--
	skip_daily = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Skip 1 Day", grant = "SkipDaily", amount = 1 },
	},
	skip_playtime = {
		productId = 0,
		productType = "devproduct",
		meta = { name = "Skip All", grant = "SkipPlaytime", amount = 0 },
	},
}

type ProductsMethods = {
	GetByProductId: (self: ProductsRegistry, productId: number) -> ProductEntry?,
	GetByGiftId: (self: ProductsRegistry, giftId: number) -> ProductEntry?,
	GetCashMultiplier: (self: ProductsRegistry, owned: { string }?) -> number,
	GetStatBonus: (self: ProductsRegistry, owned: { string }?, statKey: string) -> number,
	GetRobuxPrice: (self: ProductsRegistry, entryId: string) -> number?,
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

	GetRobuxPrice = function(self: ProductsRegistry, entryId: string): number?
		local entry = self:Get(entryId)
		if not entry then
			warn(`[Products] Attempted to get price for unknown product: {entryId}`)
			return nil
		end

		local success, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(entry.productId, GetInfoType(entry.productType))
		end)

		if not success then
			warn(`[Products] Failed to fetch product info for {entryId}: {info}`)
			return nil
		end

		return info and info.PriceInRobux
	end,
}

local ProductsRegistry: ProductsRegistry = Registry.Build("Products", list, methods)

return ProductsRegistry
