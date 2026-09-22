--!strict
-- DAT_Shop ItemNumber positions from Lemon Cake. Repeated purchases keep their saved upgrade ID.
-- Outfit Upgrade and Speed Boost have no corresponding system here, so their cells stay empty.
export type Purchase = { Id: string, Level: number }

return {
	Slots = {
		[0] = { "TopSlot" },
		[1] = { "SlotL" },
		[2] = { "SlotR" },
		[3] = { "Row3L", "Slot1" },
		[4] = { "Row3L", "Slot2" },
		[5] = { "Row3R", "Slot1" },
		[6] = { "Row3R", "Slot2" },
		[7] = { "Row4L", "Slot1" },
		[8] = { "Row4L", "Slot2" },
		[9] = { "Row4R", "Slot1" },
		[10] = { "Row4R", "Slot2" },
		[11] = { "FinalSlot" },
	},
	Categories = {
		Cafe = {
			[0] = { Id = "cafe_display", Level = 1 },
			[1] = { Id = "cafe_display", Level = 2 },
			[3] = { Id = "cafe_display", Level = 3 },
			[4] = { Id = "cafe_window", Level = 1 },
			[5] = { Id = "cafe_display", Level = 4 },
			[6] = { Id = "cafe_catcafe", Level = 1 },
			[7] = { Id = "cafe_coffee", Level = 1 },
			[8] = { Id = "cafe_display", Level = 5 },
			[9] = { Id = "cafe_tables", Level = 1 },
			[10] = { Id = "cafe_catcafe", Level = 2 },
			[11] = { Id = "cafe_assistant", Level = 1 },
		},
		Kitchen = {
			[0] = { Id = "kitchen_counter", Level = 1 },
			[1] = { Id = "kitchen_fuel", Level = 1 },
			[2] = { Id = "kitchen_oven", Level = 1 },
			[3] = { Id = "kitchen_cow", Level = 1 },
			[4] = { Id = "kitchen_chickens", Level = 1 },
			[6] = { Id = "kitchen_oven", Level = 2 },
			[7] = { Id = "kitchen_freezer", Level = 1 },
			[8] = { Id = "kitchen_brush", Level = 1 },
			[9] = { Id = "kitchen_sprint", Level = 1 },
			[10] = { Id = "kitchen_burnguard", Level = 1 },
		},
		Garden = {
			[0] = { Id = "garden_cocoa", Level = 1 },
			[1] = { Id = "garden_cherry", Level = 1 },
			[2] = { Id = "garden_strawberry", Level = 1 },
			[3] = { Id = "garden_blueberry", Level = 1 },
			[4] = { Id = "garden_water", Level = 1 },
			[5] = { Id = "garden_grape", Level = 1 },
			[6] = { Id = "garden_cart", Level = 1 },
			[7] = { Id = "garden_carrot", Level = 1 },
			[8] = { Id = "garden_sprinkler", Level = 1 },
			[9] = { Id = "garden_apple", Level = 1 },
			[10] = { Id = "garden_beehive", Level = 1 },
			[11] = { Id = "garden_lemon", Level = 1 },
		},
	} :: { [string]: { [number]: Purchase } },
}
