--!strict
-- Two dining places per table; seat and food attachments share the same index on reference anchors.
return {
	SeatCount = 2,
	SeatAttachment = "GuestSeat",
	SeatName = "Seat",
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
