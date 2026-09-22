--!strict
-- This data gets reset each session
-- Data gets initialized and edited with other systems durning runtime

-- All gameplay state of the day lives here: it replicates itself, no separate state packets needed.
-- Timers are stored as phase timestamps (workspace:GetServerTimeNow), not as progress — the oven
-- dial can derive its fraction from the start/end pair without replicating every tick.
local GameTypes = require(game:GetService("ReplicatedStorage").Shared.GameTypes)

return {
	Tutorial = {
		Stage = "Cook",
		RecipeId = "",
		GuestId = "",
		TableId = "",
		SeatIndex = 0,
		Protected = false,
		LastSale = 0,
		SaleAt = 0,
		CompletedAt = 0,
		OvenLesson = false,
	},
	Day = {
		Number = 1,
		-- "Prep" | "Shift" | "Summary"
		Phase = "Prep",
		-- End of the shift; 0 during untimed prep and summary
		EndsAt = 0,
		-- Frozen local simulation time during the evening report/menu.
		SummaryStartedAt = 0,
		-- Recipes picked for the day
		Menu = {} :: { string },
		-- Evening draft. It is copied from Menu at closing and committed by Next Day.
		NextMenu = {} :: { string },
		Summary = {
			Coins = 0,
			XP = 0,
			Served = 0,
			Lost = 0,
			Baked = 0,
			Burned = 0,
			Perfect = 0,
			Good = 0,
			Late = 0,
		},
	},

	-- What the player carries, oldest first.
	Hands = {} :: { GameTypes.ItemStack },

	-- Recipe currently selected from the persistent kitchen HUD.
	Cooking = {
		SelectedRecipeId = nil :: string?,
	},

	-- [stationId] = station state
	Stations = {} :: {
		[string]: {
			Kind: string,
			State: string,
			RecipeId: string?,
			PhaseStartedAt: number,
			ReadyAt: number,
			BurnAt: number,
			Fuel: number,
			FuelEndsAt: number,
			HeatPausedAt: number,
			Loaded: { [string]: number },
		},
	},

	-- [slotIndex] = recipeId of the finished dish on the display
	Display = {} :: { [number]: string },
	-- Overnight packages retain their recipe only to recover their original base price.
	DisplayLeftovers = {} :: { [number]: boolean },

	-- [tableId] = table state
	Tables = {} :: { [string]: GameTypes.CafeTable },

	-- [customerId] = customer waiting to be served
	Customers = {} :: {
		[string]: {
			TypeId: string,
			Kind: string,
			State: GameTypes.CustomerState,
			TableId: string?,
			SeatIndex: number?,
			QueuePosition: number?,
			DisplayPosition: number?,
			DisplaySlot: number?,
			BrowseEndsAt: number?,
			RoamAt: number?,
			PurchaseEndsAt: number?,
			CatId: string?,
			AdoptEndsAt: number?,
			Orders: { string },
			Patience: number,
			TutorialProtected: boolean,
			PatienceEndsAt: number,
			ChoosingEndsAt: number,
			OrderStartedAt: number,
			-- Only set once the last order is served: until then the seat is not freed.
			EatEndsAt: number,
		},
	},

	-- [spillId] = true
	Spills = {} :: { [string]: boolean },

	-- True after the player has mopped a spill this session: the tutorial reads it.
	HasMopped = false,

	-- Playtime rewards. They reset with the session on purpose, so the screen says so.
	-- StartedAt is workspace:GetServerTimeNow at join; the client counts up from it rather than
	-- being told the elapsed seconds every tick.
	Playtime = {
		StartedAt = 0,
		-- Tier indexes already taken
		Claimed = {} :: { number },
	},
}
