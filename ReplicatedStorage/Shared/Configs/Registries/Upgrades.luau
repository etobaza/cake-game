--!strict
-- Upgrade registry: each one moves exactly one BaseStats key by perLevel per level.
-- The buy order and every price follow the design sheet: cost gates progression, not player level,
-- so unlockLevel is 1 everywhere and `requires` chains carry the intended order.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BaseStats = require(_Configs.BaseStats)
local Garden = require(_Configs.Garden)
local GameTypes = require(_Shared.GameTypes)
local Registry = require(_Shared.Registry)

-- The authored shape; Registry.Build stamps `id` onto every entry.
type UpgradeDefinition = {
	name: string,
	-- Per-level display names for the multi-buy nodes ("Second Oven", "Third Oven"). The next
	-- unbought level names the node; a maxed node wears the last name. Missing means `name` always.
	names: { string }?,
	category: GameTypes.UpgradeCategory,
	stat: BaseStats.StatKey,
	perLevel: number,
	maxLevel: number,
	baseCost: number,
	-- Price of the next level = baseCost * costMultiplier ^ levels already bought...
	costMultiplier: number,
	-- ...unless the design sheet priced every level by hand: then `costs[level + 1]` wins.
	costs: { number }?,
	unlockLevel: number,
	-- One line for the shop: what the player actually gets.
	blurb: string,
	-- Upgrade tree: the node this one grows from, and where it sits in its category grid.
	-- A node with no parent is a root. Rows go down, columns left to right.
	requires: string?,
	prerequisites: { string }?,
	row: number,
	col: number,
}
export type UpgradeEntry = UpgradeDefinition & { id: string }

local list: { [string]: UpgradeDefinition } = {
	--[[ Cafe (the "Store" tab) ]]--
	cafe_display = {
		name = "Display Counter",
		category = "Cafe",
		stat = "DisplaySlots",
		perLevel = 1,
		maxLevel = 5,
		baseCost = 5.25,
		costMultiplier = 1,
		costs = { 5.25, 12.50, 25.00, 55.25, 75.25 },
		unlockLevel = 1,
		blurb = "Room for one more pastry in the window.",
		row = 0,
		col = 1,
	},
	cafe_window = {
		name = "Kitchen Window",
		category = "Cafe",
		stat = "TipMult",
		perLevel = 0.15,
		maxLevel = 1,
		baseCost = 210.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A serving window: guests get their food warmer and tip better.",
		requires = "cafe_display",
		row = 1,
		col = 0,
	},
	cafe_catcafe = {
		name = "Cat Café",
		names = { "Cat Café", "Cat Café Upgrade" },
		category = "Cafe",
		stat = "TipMult",
		perLevel = 0.25,
		maxLevel = 2,
		baseCost = 135.00,
		costMultiplier = 1,
		costs = { 135.00, 375.00 },
		unlockLevel = 1,
		blurb = "Cats in the café: happier guests, fatter tips.",
		requires = "cafe_display",
		row = 1,
		col = 2,
	},
	cafe_coffee = {
		name = "Coffee Machine",
		category = "Cafe",
		stat = "CoffeeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 275.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A coffee machine; coffee joins the day menu.",
		requires = "cafe_window",
		row = 2,
		col = 0,
	},
	cafe_tables = {
		name = "Two Seats & Table",
		category = "Cafe",
		stat = "TableCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 290.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Another table with two independent seats for guests.",
		requires = "cafe_catcafe",
		row = 2,
		col = 2,
	},
	cafe_assistant = {
		name = "Assistant",
		category = "Cafe",
		stat = "AssistantSlots",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 500.00,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "An assistant takes over one job for the day.",
		requires = "cafe_coffee",
		row = 3,
		col = 0,
	},

	--[[ Kitchen ]]--
	kitchen_counter = {
		name = "Kitchen Counter",
		category = "Kitchen",
		stat = "MixSpeedMult",
		perLevel = 0.25,
		maxLevel = 1,
		baseCost = 9.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A proper prep counter: the mixer works through a batch faster.",
		row = 0,
		col = 1,
	},
	kitchen_fuel = {
		name = "Firewood Upgrade",
		category = "Kitchen",
		stat = "FuelBurnSeconds",
		perLevel = 90,
		maxLevel = 1,
		baseCost = 22.25,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Firewood burns twice as long before the oven needs another log.",
		requires = "kitchen_counter",
		row = 1,
		col = 0,
	},
	kitchen_oven = {
		name = "Second Oven",
		names = { "Second Oven", "Third Oven" },
		category = "Kitchen",
		stat = "OvenCount",
		perLevel = 1,
		maxLevel = 2,
		baseCost = 85.75,
		costMultiplier = 1,
		costs = { 85.75, 245.50 },
		unlockLevel = 1,
		blurb = "One more oven, one more bake at a time.",
		requires = "kitchen_counter",
		row = 1,
		col = 2,
	},
	kitchen_chickens = {
		name = "Chickens",
		category = "Kitchen",
		stat = "AnimalCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 55.25,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Chickens in the garden: fresh eggs every day.",
		requires = "kitchen_fuel",
		row = 2,
		col = 0,
	},
	kitchen_cow = {
		name = "Cow",
		category = "Kitchen",
		stat = "AnimalCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 195.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A cow of your own: milk for the cream recipes.",
		requires = "kitchen_fuel",
		row = 2,
		col = 1,
	},
	kitchen_freezer = {
		name = "Freezer",
		category = "Kitchen",
		stat = "FreezerCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 225.75,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A freezer; frozen desserts become cookable.",
		requires = "kitchen_oven",
		row = 2,
		col = 2,
	},
	kitchen_burnguard = {
		name = "Oven Upgrade",
		category = "Kitchen",
		stat = "BurnTimeMult",
		perLevel = 0.5,
		maxLevel = 1,
		baseCost = 210.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Ready food sits longer before it burns.",
		requires = "kitchen_oven",
		row = 2,
		col = 3,
	},
	kitchen_sprint = {
		name = "Quick Sprint",
		category = "Kitchen",
		stat = "RunSpeed",
		perLevel = 4,
		maxLevel = 1,
		baseCost = 230.00,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Lighter shoes: you run noticeably faster.",
		requires = "kitchen_cow",
		row = 3,
		col = 1,
	},
	kitchen_brush = {
		name = "Animal Brush",
		category = "Kitchen",
		stat = "AnimalBrush",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 165.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Brushed animals stay clean until the next day.",
		requires = "kitchen_chickens",
		row = 3,
		col = 0,
	},
	--[[ Greenhouse: the twelve individual Lemon Cake purchases. ]]--
	garden_cocoa = {
		name = "Cocoa Tree",
		category = "Garden",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 7.25,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Cocoa grows after watering.",
		row = 0,
		col = 1,
	},
	garden_cherry = {
		name = "Cherry Tree",
		category = "Garden",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 25.75,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Fresh cherries from a watered tree.",
		row = 1,
		col = 0,
		requires = "garden_cocoa",
	},
	garden_strawberry = {
		name = "Strawberry Plant",
		category = "Garden",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 12.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow strawberries in the greenhouse.",
		row = 1,
		col = 2,
		requires = "garden_cocoa",
	},
	garden_blueberry = {
		name = "Blueberry Plant",
		category = "Garden",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 42.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow blueberries in the greenhouse.",
		row = 2,
		col = 0,
		requires = "garden_cherry",
	},
	garden_water = {
		name = "Crystal Water",
		category = "Garden",
		stat = "WaterDurationMult",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 52.75,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Water lasts twice as long.",
		row = 2,
		col = 1,
		requires = "garden_cherry",
	},
	garden_grape = {
		name = "Grape Vine",
		category = "Garden",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 90.00,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow grapes on the vine.",
		row = 2,
		col = 2,
		requires = "garden_strawberry",
	},
	garden_cart = {
		name = "Rail Cart",
		category = "Garden",
		stat = "CartEnabled",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 120.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Load one ingredient; collect it at the kitchen. Four delivery spaces.",
		row = 2,
		col = 3,
		requires = "garden_strawberry",
	},
	garden_carrot = {
		name = "Carrot Plant",
		category = "Garden",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 180.25,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow carrots in the greenhouse.",
		row = 3,
		col = 0,
		requires = "garden_blueberry",
	},
	garden_sprinkler = {
		name = "Sprinkler",
		category = "Garden",
		stat = "AutoWater",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 345.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Keeps plants and trees watered while the bakery is active.",
		row = 3,
		col = 1,
		requires = "garden_water",
	},
	garden_apple = {
		name = "Apple Tree",
		category = "Garden",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 210.00,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow apples on a watered tree.",
		row = 3,
		col = 2,
		requires = "garden_grape",
	},
	garden_beehive = {
		name = "Beehive",
		category = "Garden",
		stat = "GrowthSpeedMult",
		perLevel = Garden.PollinationBonus,
		maxLevel = 1,
		baseCost = 225.50,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Produces honey and helps plants grow 25% faster.",
		row = 3,
		col = 3,
		requires = "garden_cart",
	},
	garden_lemon = {
		name = "Lemon Tree",
		category = "Garden",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 415.00,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "The final greenhouse tree. Requires all other greenhouse upgrades.",
		row = 4,
		col = 1,
		prerequisites = {
			"garden_cocoa",
			"garden_cherry",
			"garden_strawberry",
			"garden_blueberry",
			"garden_water",
			"garden_grape",
			"garden_cart",
			"garden_carrot",
			"garden_sprinkler",
			"garden_apple",
			"garden_beehive",
		},
	},
}

type UpgradesMethods = {
	GetRemainingCost: (self: UpgradesRegistry, levels: { [string]: number }) -> number,
	GetMissingRequirement: (self: UpgradesRegistry, entry: UpgradeEntry, levels: { [string]: number }) -> string?,
	GetBranch: (self: UpgradesRegistry, category: GameTypes.UpgradeCategory) -> { UpgradeEntry },
	GetCost: (self: UpgradesRegistry, upgradeId: string, currentLevel: number) -> number?,
	GetDisplayName: (self: UpgradesRegistry, upgradeId: string, currentLevel: number) -> string,
}
export type UpgradesRegistry = Registry.Registry<UpgradeEntry> & UpgradesMethods

local methods: UpgradesMethods = {
	-- Sum in cents so an admin budget covers every remaining level without float drift.
	GetRemainingCost = function(self: UpgradesRegistry, levels: { [string]: number }): number
		local cents = 0
		for _, entry in self:Values() do
			for level = levels[entry.id] or 0, entry.maxLevel - 1 do
				local cost: number? = self:GetCost(entry.id, level)
				if cost then
					cents += math.round(cost * 100)
				end
			end
		end
		return cents / 100
	end,

	GetMissingRequirement = function(
		_self: UpgradesRegistry,
		entry: UpgradeEntry,
		levels: { [string]: number }
	): string?
		if entry.requires and (levels[entry.requires] or 0) <= 0 then
			return entry.requires
		end
		for _, id in (entry.prerequisites or {}) :: { string } do
			if (levels[id] or 0) <= 0 then
				return id
			end
		end
		return nil
	end,

	-- Every upgrade of one category, in drawing order: top row first, left to right.
	GetBranch = function(self: UpgradesRegistry, category: GameTypes.UpgradeCategory): { UpgradeEntry }
		local branch = self:Query()
			:Where(function(entry: UpgradeEntry)
				return entry.category == category
			end)
			:ToArray()

		table.sort(branch, function(left: UpgradeEntry, right: UpgradeEntry)
			if left.row == right.row then
				return left.col < right.col
			end

			return left.row < right.row
		end)

		return branch
	end,

	-- Price of the next level; nil if the upgrade is already maxed.
	GetCost = function(self: UpgradesRegistry, upgradeId: string, currentLevel: number): number?
		local entry: UpgradeEntry? = self:Get(upgradeId)
		if not entry or currentLevel >= entry.maxLevel then
			return nil
		end

		local costs = entry.costs
		if costs then
			return costs[currentLevel + 1]
		end

		return math.round(entry.baseCost * entry.costMultiplier ^ currentLevel * 100) / 100
	end,

	-- Node name at this owned level: the next unbought level names it, a maxed one wears the last.
	GetDisplayName = function(self: UpgradesRegistry, upgradeId: string, currentLevel: number): string
		local entry: UpgradeEntry? = self:Get(upgradeId)
		if not entry then
			return upgradeId
		end

		local names = entry.names
		if not names then
			return entry.name
		end

		return names[math.min(currentLevel + 1, entry.maxLevel)] or entry.name
	end,
}

local UpgradesRegistry: UpgradesRegistry = Registry.Build("Upgrades", list, methods)

return UpgradesRegistry
