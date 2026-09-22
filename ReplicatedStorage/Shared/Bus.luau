local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Shared.Libs.Packet)

return {
	Admin = {
		-- Server checks access, target, bounds and a one-use confirmation before mutation.
		Request = Packet("AdminRequest", Packet.String, Packet.NumberF64, Packet.NumberF64, Packet.String):Response(Packet.Any),
	},
	Tutorial = {
		-- Client -> Server: presentation preferences and skip intent; never step completion.
		Control = Packet("TutorialControl", Packet.String, Packet.String), -- action, value
	},
	VFX = {
		-- Server -> Client: an accepted world action; clients never request particle playback.
		Burst = Packet(
			"VFXBurst",
			Packet.String,
			Packet.Instance,
			Packet.CFrameF32U16,
			Packet.NumberF64,
			Packet.NumberF64
		), -- effect, target, frame, ownerUserId, serverTime
	},
	-- CORE
	Data = {
		GetCloud = Packet("DataGetCloud", Packet.Nil):Response(Packet.Any),
		GetSession = Packet("DataGetSession", Packet.Nil):Response(Packet.Any),
		Update = Packet("DataUpdate", { Cloud = { Packet.Any }, Session = { Packet.Any } }),
	},

	Purchase = {
		-- Client -> Server: Request purchase prompt
		RequestPurchase = Packet("PurchaseRequest", Packet.NumberU32), -- productId
		-- Client -> Server: Request gift purchase
		RequestGift = Packet("PurchaseRequestGift", Packet.NumberU32, Packet.NumberU32), -- productId, recipientUserId
		-- Server -> Client: Purchase completed notification
		Completed = Packet("PurchaseCompleted", Packet.NumberU32, Packet.Boolean8), -- productId, isGift
		-- Server -> Client: Purchase failed notification
		Failed = Packet("PurchaseFailed", Packet.NumberU32, Packet.String), -- productId, errorMessage
	},

	-- GAMEPLAY
	-- The client sends intent only; all state is decided and replicated by the server (Session data).
	Day = {
		-- Client -> Server: edit tomorrow's recipes during the end-of-day summary
		SelectMenu = Packet("DaySelectMenu", { Packet.String }), -- recipeIds
		-- Client -> Server: open the bakery, start the shift
		Open = Packet("DayOpen", Packet.Nil),
		-- Client -> Server: toggle the bakery from its owned entrance prompt
		ToggleDoor = Packet("DayToggleDoor", Packet.String), -- doorId
		-- Client -> Server: commit tomorrow's menu and enter its untimed prep
		Next = Packet("DayNext", Packet.Nil),
		-- Server -> Client: the shift ended, the summary is in Session.Day.Summary
		ShiftEnded = Packet("DayShiftEnded", Packet.Nil),
		-- Server -> Client: new level
		LevelUp = Packet("DayLevelUp", Packet.NumberU8), -- level
		-- Server -> Client: the level unlocked a new story chapter
		StoryUnlocked = Packet("DayStoryUnlocked", Packet.NumberU8), -- stage
	},

	Player = {
		-- Client -> Server: the player started or stopped running
		SetRunning = Packet("PlayerSetRunning", Packet.Boolean8), -- isRunning
		-- Server -> Client: an accepted work action should play its character animation
		PlayAction = Packet("PlayerPlayAction", Packet.String), -- actionName
	},

	Kitchen = {
		-- Client -> Server: choose which recipe the kitchen is preparing
		SelectRecipe = Packet("KitchenSelectRecipe", Packet.String), -- recipeId
		-- Client -> Server: take one ingredient from its pantry dispenser
		TakeIngredient = Packet("KitchenTakeIngredient", Packet.String), -- dispenserId
		-- Client -> Server: put an infinite ingredient back at its original dispenser
		ReturnIngredient = Packet("KitchenReturnIngredient", Packet.String), -- dispenserId
		-- Client -> Server: take stored garden produce while standing at the mixer
		TakePantry = Packet("KitchenTakePantry", Packet.String, Packet.String), -- stationId, ingredientId
		-- Client -> Server: start the selected recipe on its first station
		Mix = Packet("KitchenMix", Packet.String), -- stationId
		-- Client -> Server: put what is in hands onto a station
		Load = Packet("KitchenLoad", Packet.String), -- stationId
		-- Client -> Server: drop the selected recipe at an idle mixer; loaded produce goes back to the pantry
		Cancel = Packet("KitchenCancel", Packet.String), -- stationId
		-- Client -> Server: take from a station into hands
		Collect = Packet("KitchenCollect", Packet.String), -- stationId
		-- Client -> Server: take one log from the firewood pile
		TakeFirewood = Packet("KitchenTakeFirewood", Packet.String), -- buildingId
		-- Client -> Server: put the log from hands into an oven
		Refuel = Packet("KitchenRefuel", Packet.String), -- stationId
		-- Client -> Server: throw away what is in hands at a trash bin
		Trash = Packet("KitchenTrash", Packet.String), -- trashId
	},

	Cafe = {
		-- Client -> Server: pet an owned cat, or give the play-area cat carried milk.
		CatInteract = Packet("CafeCatInteract", Packet.String), -- unique daily cat ID
		-- Client -> Server: ask a choosing guest at an owned nearby table for their order
		TakeOrder = Packet("CafeTakeOrder", Packet.String), -- customerId
		-- Client -> Server: put a dish from hands onto the display
		DisplayPlace = Packet("CafeDisplayPlace", Packet.NumberU8), -- slotIndex
		-- Client -> Server: take a dish from the display into hands
		DisplayTake = Packet("CafeDisplayTake", Packet.NumberU8), -- slotIndex
		-- Client -> Server: clean a dirty table
		CleanTable = Packet("CafeCleanTable", Packet.String), -- tableId
		-- Client -> Server: serve what is in hands to a customer
		Serve = Packet("CafeServe", Packet.String), -- customerId
		-- Client -> Server: mop a spill
		CleanSpill = Packet("CafeCleanSpill", Packet.String), -- spillId
		-- Client -> Server: pick up the broom (or put it back)
		TakeTool = Packet("CafeTakeTool", Packet.String), -- buildingId
		ReturnTool = Packet("CafeReturnTool", Packet.String), -- buildingId
	},

	Garden = {
		-- Client -> Server: load one carried ingredient at the garden cart
		CartLoad = Packet("GardenCartLoad", Packet.String), -- cartId
		-- Client -> Server: take this exact parked cart, including when adjacent ingredients match
		CartTake = Packet("GardenCartTake", Packet.String, Packet.String, Packet.String), -- outputId, expectedIngredientId, expectedCartId
		-- Client -> Server: water a garden plot
		Water = Packet("GardenWater", Packet.String), -- plotId
		-- Client -> Server: brush an animal with empty hands
		Brush = Packet("GardenBrush", Packet.String), -- animalId
		-- Client -> Server: harvest one crop or animal produce into hands
		Harvest = Packet("GardenHarvest", Packet.String), -- plotId | animalId
	},

	Progress = {
		-- Client -> Server: buy the next upgrade level
		BuyUpgrade = Packet("ProgressBuyUpgrade", Packet.String, Packet.NumberU8), -- upgradeId, purchaseLevel
		-- Client -> Server: assign the assistant task for the next day during Summary
		SetAssistantTask = Packet("ProgressSetAssistantTask", Packet.String), -- taskId
		-- Client -> Server: redeem a promo code typed into the codes screen
		RedeemCode = Packet("ProgressRedeemCode", Packet.String), -- code
		-- Client -> Server: take today's daily reward
		ClaimDaily = Packet("ProgressClaimDaily", Packet.Nil),
		-- Client -> Server: take one playtime tier
		ClaimPlaytime = Packet("ProgressClaimPlaytime", Packet.NumberU8), -- tier index
		-- Server -> Client: a reward was handed out, text for a toast
		RewardGranted = Packet("ProgressRewardGranted", Packet.String), -- message
		-- Server -> Client: the action was rejected, reason for a toast
		ActionFailed = Packet("ProgressActionFailed", Packet.String), -- reason
	},
}
