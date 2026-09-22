-- This data gets saved in to the cloud

return {
	CurrentClass = "warrior",

	Cash = 25,
	-- Admin reset is consumed before gameplay handlers receive the next loaded profile.
	ProgressResetPending = false,

	Skins = {},

	Stats = {
		RobuxSpent = 0,
	},

	-- Base state: Upgrades = [upgradeId] = level
	Base = {
		Version = 1,
		Upgrades = {} :: { [string]: number },
	},

	-- Bakery progress. Unlocked recipes are not stored — they follow from Level.
	Level = 1,
	XP = 0,
	Day = 1,
	-- Daily cats survive reconnects; adopted cats cannot pay again in the same day.
	CatCafe = { Day = 0, Level = 0, Cats = {} :: { [string]: any } },
	-- Menu fixed for the current day. New profiles start with the three staple-only Lemon Cake recipes;
	-- the evening planner replaces it only when Next Day is confirmed.
	DayMenu = { "bread", "sweet_roll", "marshmallow_twist" } :: { string },
	-- Zero also reconciles older profiles; DayCycleHandler upgrades their menu before opening.
	RecipeCatalogVersion = 0,
	Tutorial = {
		Version = 0,
		Status = "Active",
		Actions = {} :: { [string]: boolean },
		Lessons = {} :: { [string]: boolean },
		Collapsed = false,
	},

	-- [recipeId] = day number until which the dish still counts as new and adds a tip bonus
	NewRecipeUntilDay = {} :: { [string]: number },

	-- Unlocked story chapter: moved by level rewards
	StoryStage = 0,

	-- Pantry of garden ingredients: [ingredientId] = amount
	Pantry = {} :: { [string]: number },

	-- One-off starter grants. Kept as explicit flags because "is this table still empty" cannot be
	-- asked of replicated data: iterating a proxy table always reads as empty and the grant repeats.
	StarterPantryGiven = false,
	StarterRecipesMarked = false,

	-- The garden survives the day change: watering, readiness and unharvested stock
	GardenVersion = 0,
	GardenCart = {
		Version = 0,
		Day = 0,
		NextId = 0,
		SpawnRemaining = 0,
		Queue = {} :: { string },
		Carts = {} :: { any },
	},
	Garden = {
		Plots = {} :: { [string]: any },
		Trees = {} :: { [string]: any },
		Animals = {} :: { [string]: any },
	},

	-- Assistant task for the day: "None" | "Tables" | "Coffee" | "Display"
	AssistantTask = "None",

	-- Rewards handed out outside the shift: promo codes and the daily streak.
	-- Days is how far the streak has gone; ClaimedAt is os.time of the last claim, and the two
	-- together decide whether the next day is ready, still cooling down, or a broken streak.
	Rewards = {
		Codes = {} :: { string },
		Day = 0,
		ClaimedAt = 0,
	},

	-- Registry ids of the gamepasses and permanent products this player owns. Written by the server
	-- from MarketplaceService on join and after every purchase; read by the economy, the stats and
	-- the store screen. The receipt cache below is the durable record, this is the readable one.
	Passes = {} :: { string },

	-- Bought gamepasses / products / receipt ids
	_productCache = {},
}
