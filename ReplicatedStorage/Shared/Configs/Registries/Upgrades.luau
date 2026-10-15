--!strict
-- Upgrade registry: each one moves one BaseStats key by perLevel per level. Buildings an upgrade
-- adds (garden sources, animals, the rail cart) are placed by its ID, so their stat only counts them.
-- The buy order and every price (times 100, in whole coins) follow the design sheet: cost gates
-- progression, not player level, so unlockLevel is 1 everywhere and `requires` chains carry the
-- intended order.

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
	-- Upgrade-tree node art (uploaded group image). Missing means the node shows its name only.
	icon: string?,
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
	-- Upgrade tree: the node this one grows from; a node with no parent is a root. Configs/UpgradeTree
	-- places each purchase in its Lemon Cake cell.
	requires: string?,
	prerequisites: { string }?,
}
export type UpgradeEntry = UpgradeDefinition & { id: string }

export type UpgradeGoal = { Id: string, Level: number, Cost: number }
export type UpgradeProgress = {
	AffordableCount: number,
	Recommended: UpgradeGoal?,
	Goal: UpgradeGoal?,
	Complete: boolean,
}
-- The three replicated Cloud values every progress read needs, with the shared defaults applied.
export type UpgradeInputs = { Levels: { [string]: number }, PlayerLevel: number, Cash: number }

local list: { [string]: UpgradeDefinition } = {
	--[[ Cafe (the "Store" tab) ]]--
	cafe_display = {
		name = "Display Counter",
		category = "Cafe",
		icon = "rbxassetid://120360343831546",
		stat = "DisplaySlots",
		perLevel = 1,
		maxLevel = 5,
		baseCost = 525,
		costMultiplier = 1,
		costs = { 525, 1250, 2500, 5525, 7525 },
		unlockLevel = 1,
		blurb = "Room for one more pastry in the window.",
	},
	cafe_window = {
		name = "Kitchen Window",
		category = "Cafe",
		icon = "rbxassetid://128922515596950",
		stat = "WindowSlots",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 21050,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A pass-through shelf: leave a pastry from the kitchen, pick it up in the café.",
		requires = "cafe_display",
	},
	cafe_catcafe = {
		name = "Cat Café",
		names = { "Cat Café", "Cat Café Upgrade" },
		category = "Cafe",
		icon = "rbxassetid://79770338871756",
		stat = "TipMult",
		perLevel = 0.25,
		maxLevel = 2,
		baseCost = 13500,
		costMultiplier = 1,
		costs = { 13500, 37500 },
		unlockLevel = 1,
		blurb = "Cats in the café: happier guests, fatter tips.",
		requires = "cafe_display",
	},
	cafe_coffee = {
		name = "Coffee Machine",
		category = "Cafe",
		icon = "rbxassetid://100738216830028",
		stat = "CoffeeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 27550,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A coffee machine; coffee joins the day menu.",
		requires = "cafe_window",
	},
	cafe_tables = {
		name = "Two Seats & Table",
		category = "Cafe",
		icon = "rbxassetid://90049173564855",
		stat = "TableCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 29050,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Another table with two independent seats for guests.",
		requires = "cafe_catcafe",
	},
	cafe_assistant = {
		name = "Assistant",
		category = "Cafe",
		icon = "rbxassetid://130098577932473",
		stat = "AssistantSlots",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 50000,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "An assistant carries window pastries, serves coffee, clears tables and stocks the display.",
		requires = "cafe_coffee",
	},

	--[[ Kitchen ]]--
	kitchen_counter = {
		name = "Kitchen Counter",
		category = "Kitchen",
		icon = "rbxassetid://80514081518797",
		stat = "MixSpeedMult",
		perLevel = 0.25,
		maxLevel = 1,
		baseCost = 950,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A proper prep counter: the mixer works through a batch faster.",
	},
	kitchen_fuel = {
		name = "Firewood Upgrade",
		category = "Kitchen",
		icon = "rbxassetid://131748826985414",
		stat = "FuelBurnSeconds",
		perLevel = 90,
		maxLevel = 1,
		baseCost = 2225,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Firewood burns twice as long before the oven needs another log.",
		requires = "kitchen_counter",
	},
	kitchen_oven = {
		name = "Second Oven",
		names = { "Second Oven", "Third Oven" },
		category = "Kitchen",
		icon = "rbxassetid://87215803734699",
		stat = "OvenCount",
		perLevel = 1,
		maxLevel = 2,
		baseCost = 8575,
		costMultiplier = 1,
		costs = { 8575, 24550 },
		unlockLevel = 1,
		blurb = "One more oven, one more bake at a time.",
		requires = "kitchen_counter",
	},
	kitchen_chickens = {
		name = "Chickens",
		category = "Kitchen",
		icon = "rbxassetid://95634191878600",
		stat = "AnimalCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 5525,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Chickens in the garden: fresh eggs every day.",
		requires = "kitchen_fuel",
	},
	kitchen_cow = {
		name = "Cow",
		category = "Kitchen",
		icon = "rbxassetid://136554018438275",
		stat = "AnimalCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 19550,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A cow of your own: milk for the cream recipes.",
		requires = "kitchen_fuel",
	},
	kitchen_freezer = {
		name = "Freezer",
		category = "Kitchen",
		icon = "rbxassetid://125223756584156",
		stat = "FreezerCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 22575,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "A freezer; frozen desserts become cookable.",
		requires = "kitchen_oven",
	},
	kitchen_burnguard = {
		name = "Oven Upgrade",
		category = "Kitchen",
		icon = "rbxassetid://136579831356225",
		stat = "BurnTimeMult",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 21050,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Ready food has 60 seconds before it burns instead of 30.",
		requires = "kitchen_oven",
	},
	kitchen_sprint = {
		name = "Quick Sprint",
		category = "Kitchen",
		icon = "rbxassetid://79449077398822",
		stat = "RunSpeed",
		perLevel = 4,
		maxLevel = 1,
		baseCost = 23000,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Lighter shoes: you run noticeably faster.",
		requires = "kitchen_cow",
	},
	kitchen_brush = {
		name = "Animal Brush",
		category = "Kitchen",
		icon = "rbxassetid://81594019991717",
		stat = "AnimalBrush",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 16550,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Brushed animals stay clean until the next day.",
		requires = "kitchen_chickens",
	},
	--[[ Greenhouse: the twelve individual Lemon Cake purchases. ]]--
	garden_cocoa = {
		name = "Cocoa Tree",
		category = "Garden",
		icon = "rbxassetid://129236421655311",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 725,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Cocoa grows after watering.",
	},
	garden_cherry = {
		name = "Cherry Tree",
		category = "Garden",
		icon = "rbxassetid://108816003875695",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 2575,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Fresh cherries from a watered tree.",
		requires = "garden_cocoa",
	},
	garden_strawberry = {
		name = "Strawberry Plant",
		category = "Garden",
		icon = "rbxassetid://76711374259891",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 1250,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow strawberries in the greenhouse.",
		requires = "garden_cocoa",
	},
	garden_blueberry = {
		name = "Blueberry Plant",
		category = "Garden",
		icon = "rbxassetid://131771665195322",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 4250,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow blueberries in the greenhouse.",
		requires = "garden_cherry",
	},
	garden_water = {
		name = "Crystal Water",
		category = "Garden",
		icon = "rbxassetid://82520618233243",
		stat = "WaterDurationMult",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 5275,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Water lasts twice as long.",
		requires = "garden_cherry",
	},
	garden_grape = {
		name = "Grape Vine",
		category = "Garden",
		icon = "rbxassetid://95327909700538",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 9000,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow grapes on the vine.",
		requires = "garden_strawberry",
	},
	garden_cart = {
		name = "Rail Cart",
		category = "Garden",
		icon = "rbxassetid://135563460790075",
		stat = "CartEnabled",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 12050,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Load one ingredient; collect it at the kitchen. Four delivery spaces.",
		requires = "garden_strawberry",
	},
	garden_carrot = {
		name = "Carrot Plant",
		category = "Garden",
		icon = "rbxassetid://135020966597679",
		stat = "PlotCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 18025,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow carrots in the greenhouse.",
		requires = "garden_blueberry",
	},
	garden_sprinkler = {
		name = "Sprinkler",
		category = "Garden",
		icon = "rbxassetid://103537535502107",
		stat = "AutoWater",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 34550,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Keeps plants and trees watered while the bakery is active.",
		requires = "garden_water",
	},
	garden_apple = {
		name = "Apple Tree",
		category = "Garden",
		icon = "rbxassetid://76347700350100",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 21000,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Grow apples on a watered tree.",
		requires = "garden_grape",
	},
	garden_beehive = {
		name = "Beehive",
		category = "Garden",
		icon = "rbxassetid://79663462513168",
		stat = "GrowthSpeedMult",
		perLevel = Garden.PollinationBonus,
		maxLevel = 1,
		baseCost = 22550,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "Produces honey and helps plants grow 25% faster.",
		requires = "garden_cart",
	},
	garden_lemon = {
		name = "Lemon Tree",
		category = "Garden",
		icon = "rbxassetid://134500463403532",
		stat = "TreeCount",
		perLevel = 1,
		maxLevel = 1,
		baseCost = 41500,
		costMultiplier = 1,
		unlockLevel = 1,
		blurb = "The final greenhouse tree. Requires all other greenhouse upgrades.",
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
	GetPurchaseCost: (
		self: UpgradesRegistry,
		upgradeId: string,
		levels: { [string]: number },
		playerLevel: number
	) -> number?,
	GetProgress: (self: UpgradesRegistry, levels: { [string]: number }, playerLevel: number, cash: number) -> UpgradeProgress,
	ReadInputs: (self: UpgradesRegistry, data: any) -> UpgradeInputs,
	ReadProgress: (self: UpgradesRegistry, data: any) -> UpgradeProgress,
	GetRemainingCost: (self: UpgradesRegistry, levels: { [string]: number }) -> number,
	GetMissingRequirement: (self: UpgradesRegistry, entry: UpgradeEntry, levels: { [string]: number }) -> string?,
	GetCost: (self: UpgradesRegistry, upgradeId: string, currentLevel: number) -> number?,
	GetDisplayName: (self: UpgradesRegistry, upgradeId: string, currentLevel: number) -> string,
}
export type UpgradesRegistry = Registry.Registry<UpgradeEntry> & UpgradesMethods

local methods: UpgradesMethods = {
	-- The server and every progression affordance use the same next-level eligibility.
	GetPurchaseCost = function(
		self: UpgradesRegistry,
		upgradeId: string,
		levels: { [string]: number },
		playerLevel: number
	): number?
		local entry = self:Get(upgradeId)
		if not entry or playerLevel < entry.unlockLevel or self:GetMissingRequirement(entry, levels) then
			return nil
		end
		return self:GetCost(upgradeId, levels[upgradeId] or 0)
	end,

	GetProgress = function(
		self: UpgradesRegistry,
		levels: { [string]: number },
		playerLevel: number,
		cash: number
	): UpgradeProgress
		local count = 0
		local recommended: UpgradeGoal? = nil
		local lockedGoal: UpgradeGoal? = nil
		local complete = true
		for _, entry in self:Values() do
			local level = levels[entry.id] or 0
			local cost = self:GetCost(entry.id, level)
			if not cost then
				continue
			end
			complete = false
			local goal: UpgradeGoal = { Id = entry.id, Level = level + 1, Cost = cost }
			local unlocked = self:GetPurchaseCost(entry.id, levels, playerLevel) ~= nil
			if unlocked and cash >= cost then
				count += 1
			end
			local previous = if unlocked then recommended else lockedGoal
			if previous and (previous.Cost < cost or (previous.Cost == cost and previous.Id < entry.id)) then
				continue
			end
			if unlocked then
				recommended = goal
			else
				lockedGoal = goal
			end
		end
		-- Cheapest unlocked is affordable whenever any unlocked purchase is affordable.
		return {
			AffordableCount = count,
			Recommended = recommended,
			Goal = recommended or lockedGoal,
			Complete = complete,
		}
	end,

	-- `data` is the client DataClient handler (or the HUD's injected copy of it). It is passed in
	-- because Shared must not require client handlers; only its GetData(path) is used.
	ReadInputs = function(_self: UpgradesRegistry, data: any): UpgradeInputs
		return {
			Levels = data:GetData({ "Base", "Upgrades" }) or {},
			PlayerLevel = data:GetData({ "Level" }) or 1,
			Cash = data:GetData({ "Cash" }) or 0,
		}
	end,

	ReadProgress = function(self: UpgradesRegistry, data: any): UpgradeProgress
		local inputs = self:ReadInputs(data)
		return self:GetProgress(inputs.Levels, inputs.PlayerLevel, inputs.Cash)
	end,

	-- Every remaining level of every upgrade, in whole coins: the admin budget for the rest of the tree.
	GetRemainingCost = function(self: UpgradesRegistry, levels: { [string]: number }): number
		local total = 0
		for _, entry in self:Values() do
			for level = levels[entry.id] or 0, entry.maxLevel - 1 do
				local cost: number? = self:GetCost(entry.id, level)
				if cost then
					total += cost
				end
			end
		end
		return total
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

		return math.round(entry.baseCost * entry.costMultiplier ^ currentLevel)
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
