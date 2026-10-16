--!strict
-- Who walks through whom. Groups are registered once at boot by CollisionHandler; everything else
-- only names the group it belongs to.
-- The rule of the room: guests must never be blocked by anything except the shell of the building.
-- A rig wedged behind a prop never reaches its table, and the simulation keeps counting it as seated.

--[[ Tables ]]--
local Groups = {
	-- Guest bodies.
	Guest = "Guests",
	-- Player characters.
	Player = "Players",
	-- Everything standing inside the room: stations, display, tables, chairs, garden, decorations.
	Prop = "Props",
	-- Door leaves. They fill their opening, so anyone who walks the bakery has to pass through
	-- them. The open arches between zones are not doors here (see DoorFrameHolders).
	Door = "Doors",
}

local Collision = {
	Groups = Groups,

	-- Pairs that do NOT collide. Anything not listed keeps colliding, walls and floor included.
	Passable = {
		{ Groups.Guest, Groups.Guest },
		{ Groups.Guest, Groups.Player },
		{ Groups.Guest, Groups.Prop },
		{ Groups.Door, Groups.Player },
		{ Groups.Door, Groups.Guest },
	},

	-- Folders of the bakery whose parts join the prop group when a base is built. The shell of
	-- the room (walls, floor, structure) is deliberately absent: a guest must not walk out through a wall.
	PassableFolders = { "Decoration" },
	-- Bought cafe furniture lives outside Decoration and otherwise blocks dining routes.
	PassablePaths = {
		{ "1ndFloor", "Cafe", "Upgrades", "CoffeeMachine" },
		{ "1ndFloor", "Cafe", "Upgrades", "TwoSeatsTable" },
	},

	-- Holders inside a passable folder that stay solid for guests. The cafe's bay-window glass is
	-- authored under Decoration, but it is the room's outer shell: a guest leaving an empty display
	-- walked straight out through it.
	SolidPaths = {
		{ "1ndFloor", "Cafe", "Decoration", "Window" },
	},

	-- Interactions do not reach through the room's shell (Shared/WallReach): folders whose parts are
	-- the bakery's walls, matched by name anywhere under the bakery.
	WallFolders = { "WallStructure", "BrickStructure" },
	-- Some stations stand against a wall, so their prompt point sits this close behind its surface;
	-- a wall hit within this distance of the target still counts as clear.
	WallEmbedTolerance = 1.5,
	-- Building kinds meant to be used across a wall: the kitchen window serves both rooms, and the
	-- entrance door stands in the facade's opening and works from either side.
	WallExemptKinds = { "Window", "Door" },

	-- Models that ARE the doorway rather than stand next to it, matched lowercased on the whole name.
	-- Every bakery gets this at boot, not only a claimed one: a shut front door blocks the map itself.
	-- Whole-name matching on purpose — the oven's OvenDoorLeft/Right must keep colliding.
	PassableModels = { "door" },
	-- Holders whose "door" models are only a frame around an open passage (the kitchen's arches to
	-- the cafe and the garden), as paths relative to the bakery. Their mesh's own collision already
	-- leaves the opening walkable, so they stay out of the door group: the posts keep blocking
	-- players, and claimed bakeries put them in the prop group like the rest of Decoration.
	DoorFrameHolders = {
		{ "1ndFloor", "Kitchen", "Decoration" },
	},
}

return Collision
