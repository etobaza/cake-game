--!strict
-- Guest bodies in the world. The simulation lives in Session.Customers; this only says how a guest
-- looks, where they stand and how fast they walk there.
-- Offsets are measured from the building the guest came for, along that building's own facing,
-- so the numbers survive the room being re-laid out.

--[[ Tables ]]--
local Guests = {
	-- Folder the bodies go into, inside the player's base model, so the base janitor takes them down.
	FolderName = "Guests",

	Street = {
		FolderName = "StreetGuests",
		MinimumPopulation = 4,
		PopulationPerBakery = 3,
		MaxPopulation = 32,
		PersonalSpace = 4,
		SpawnInterval = 2,
		AdmissionDistance = 60,
		AdmissionRetrySeconds = 1,
		AdmissionLeadSeconds = 8,
		NearbyPopulation = 2,
		DemandSeconds = 2,
		ReturnCooldownSeconds = 8,
		MinWalkSeconds = 3,
		HalfLength = 38,
		PointSpacing = 12,
		LaneOffset = 4,
		-- Keep departure points on pavement before the decorative rocks at the street boundary.
		EndInset = 20,
		ExitTimeout = 90,
		FadeSeconds = 1,
		-- Child names below the world package root (Workspace.World).
		SidewalkPath = { "Environment", "Sidewalk" },
		SidewalkName = "Sidewalk",
	},

	--[[ Body ]]--
	-- Friends are preferred. Once used, new visitors receive generated R15 appearances.
	Avatar = {
		-- Friends are read once per visit to the server; one page of the friend list is 50 people.
		MaxFriends = 50,
		FriendLoadAttempts = 3,
		FriendRetrySeconds = 2,
		MaxCachedRigs = 48,
		AvatarRetrySeconds = 60,
		-- Texture templates from the authored ReplicatedStorage.Folder.Rig outfit.
		FallbackShirt = "http://www.roblox.com/asset/?id=144076357",
		FallbackPants = "http://www.roblox.com/asset/?id=144076759",
		-- Everyone is rebuilt as R15, so the animation ids below always match the rig.
		RigType = Enum.HumanoidRigType.R15,
		IdleAnimation = "rbxassetid://507766666",
		WalkAnimation = "rbxassetid://507777826",
		SitAnimation = "rbxassetid://2506281703",
	},

	--[[ Movement ]]--
	-- Studs per second. Slower than the player on purpose: a guest crossing the room should read
	-- as a guest arriving, not as something teleporting into a chair.
	WalkSpeed = 6,
	TurnSeconds = 0.35,
	SeatTransitionSeconds = 0.45,
	-- Advance collinear intermediate points before Humanoid decelerates to a full stop.
	WaypointReachDistance = 2.5,
	-- Follow the blue authored runner, while still allowing shorter steps off it to a destination.
	CarpetRoute = {
		Path = { "1ndFloor", "Cafe", "Decoration", "carpet" },
		MaterialVariant = "CarpetToon",
		TravelCost = 0.25,
		DirectDistance = 6,
		MaxDetourRatio = 3,
		ObstacleHeight = 2,
	},
	-- Doorway is the only guaranteed opening, so every route goes through it instead of straight
	-- through a wall. Spawn is OUTSIDE on the porch, the door step is the first point inside.
	SpawnDistance = 10,
	DoorStepDistance = 7,
	-- A leg of a walk is given up on after this: a guest wedged behind a prop must not hold the body
	-- forever, the day moves on without them.
	WalkTimeout = 8,
	-- Seat cooldown can last three seconds; retries must outlive it.
	SeatTimeout = 5,
	MoveRefreshSeconds = 1,
	-- A guest who cannot reach the door in this long is taken down where they stand. Without it a
	-- jammed body stays in the room for the rest of the day.
	ExitTimeout = 30,

	--[[ Where a guest stands ]]--
	-- A seated guest approaches behind their own chair; other guests approach the display's edge.
	SeatGap = 1.5,
	DisplayGap = 2,
	-- Shoppers stay in the aisle, on the room side of the pastry display.
	DisplayApproachDistance = 7,
	DisplayStandDistance = 5,
	-- Two waiting places stay on the porch, beside the entrance lane.
	QueueSide = 5,
	QueueOutsideDistance = 5,
	QueueGap = 4,

	-- How often the shared tick mirrors choosing state for guest VFX.
	RefreshInterval = 0.25,
}

return Guests
