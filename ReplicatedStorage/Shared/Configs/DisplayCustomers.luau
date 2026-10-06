--!strict
-- Timings and decisions recovered from Lemon Cake build 6596857, BP_Client.
return {
	BrowseMinSeconds = 5,
	BrowseMaxSeconds = 15,
	RoamPauseMinSeconds = 2,
	RoamPauseMaxSeconds = 5,
	PurchaseSeconds = 0.2,
	SeatedChance = 0.75,
	-- Visitors who found no free chair roam the room on top of the pedestal browsers. Without a
	-- pedestal they walk between random points of the café runner, as BP_Client.ClientRoam picks
	-- random points in the shop's bounding box.
	RoamGuests = 2,
	-- Roam points closer than this to the entrance are skipped, so nobody idles in the doorway.
	RoamDoorClearance = 8,
	FlowChange = 0.01,
	FlowMin = 0.5,
	FlowMax = 2,
	LeftoverPriceMultiplier = 0.5,
	PackageSize = Vector3.new(1.3, 0.8, 1.3),
	PackageColor = Color3.fromRGB(245, 215, 158),
	PackageHandOffset = CFrame.new(0, -0.65, 0),
}
