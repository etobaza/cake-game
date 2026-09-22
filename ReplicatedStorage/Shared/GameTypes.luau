--!strict
-- Shared gameplay types: used by configs and by handlers on both sides.

--[[ Tables ]]--
local GameTypes = {}

export type DayPhase = "Prep" | "Shift" | "Closing" | "Summary"
export type TutorialStage = "Cook" | "Serve" | "Clean" | "Completed" | "Skipped"
export type TutorialStatus = "Active" | "Completed" | "Skipped"
export type TutorialTarget = {
	kind: "World" | "Gui" | "Recipe" | "Order" | "Ingredient",
	id: string,
	seat: number?,
	control: string?,
}
export type TutorialGoal = {
	id: string,
	title: string,
	hint: string,
	target: TutorialTarget?,
	recipeId: string?,
	itemId: string?,
	itemKind: string?,
	recovery: boolean?,
	waiting: boolean?,
	urgent: boolean?,
	topic: string?,
}

-- Cooking station. Every recipe starts on the Mixer, then moves to its own station.
export type StationKind = "Mixer" | "Oven" | "Freezer" | "Coffee"
export type StationState = "Idle" | "Loaded" | "Mixing" | "Cooking" | "Ready" | "Burnt"

-- Burnt is only carried to the trash: it cannot be served or put on the display.
-- Tool is a held broom or similar: it occupies a hand slot and is required to mop.
-- Fuel is a log carried from the woodpile to an oven; one log is one unit of firewood.
export type ItemKind = "Dish" | "Leftover" | "Dough" | "Ingredient" | "Burnt" | "Tool" | "Fuel"
export type ItemStack = {
	Kind: ItemKind,
	Id: string,
	-- Server-assigned dispenser identity; cleared with the item on consumption or discard.
	SourceId: string?,
	-- Transient server-authored pickup presentation, never accepted from a client.
	PickupOrigin: Vector3?,
	PickupAt: number?,
}

-- Seated takes a table and waits for the order, Display picks finished dishes off the shelf.
export type CustomerKind = "Seated" | "Display"
-- Eating comes after the last order is served and still holds the table.
export type CustomerState =
	"Queued"
	| "Arriving"
	| "Choosing"
	| "Waiting"
	| "Eating"
	| "Leaving"
	| "Browsing"
	| "Shopping"
	| "Purchasing"
	| "Adopting"

export type TableSeat = {
	CustomerId: string?,
	Dirty: boolean,
	MenuHidden: boolean,
	Served: { string },
}

export type CafeTable = {
	Dirty: boolean,
	Seats: { TableSeat },
}

export type UpgradeCategory = "Cafe" | "Kitchen" | "Garden"

return GameTypes
