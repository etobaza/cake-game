--!strict
-- Two dining places per table; seat and food attachments share the same index on reference anchors.
return {
	SeatCount = 2,
	SeatAttachment = "GuestSeat",
	SeatName = "Seat",
	-- Each place gets its own prompt target (BuildingHandler/View.AttachSeatPrompts), so Take order
	-- and Serve name one guest. The part carries the place index in this attribute; the table part
	-- itself keeps cleaning.
	SeatPromptName = "SeatPrompt",
	SeatPromptAttribute = "SeatPromptIndex",
	-- Moved from the chair toward the table centre by this share, and lifted to table-top height,
	-- so the plate floats in front of the guest instead of over their speech bubble.
	SeatPromptInset = 0.4,
	SeatPromptLift = 0.6,
	-- Shorter than the default 12 studs so the nearest place wins at a crowded table.
	SeatPromptDistance = 9,
	CleanPlateAsset = "CleanPlate",
	CleanPlateSize = Vector3.new(2.05, 0.3, 2.05),
	-- The food rests in the recessed centre, below the plate's raised rim.
	CleanPlateFoodHeight = 0.11,
	DirtyPlateAsset = "DirtyPlate",
	DirtyPlateName = "plate",
	DirtyPlateSize = Vector3.new(2.05, 0.3, 2.05),
	ModelName = "Menuonta",
	CupModelName = "cofee",
	Radius = 4,
	Paths = {
		[1] = { "1ndFloor", "Cafe", "Upgrades", "TwoSeatsTable", "Upgrade" },
		[2] = { "1ndFloor", "Cafe", "Decoration" },
	},
}
