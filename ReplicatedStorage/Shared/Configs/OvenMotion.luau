--!strict
-- Replicated hinge targets; clients animate the authored leaves between server decisions.
return {
	Tag = "OvenDoorMotion",
	OpenAttribute = "OvenOpenPivot",
	ClosedAttribute = "OvenClosedPivot",
	TargetAttribute = "OvenDoorClosed",
	-- A gentle close has time to accelerate and settle without delaying cooking.
	TravelSeconds = 1.4,
}
