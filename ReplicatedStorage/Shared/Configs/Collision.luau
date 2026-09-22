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
	-- Door leaves and the arches between zones. They fill their opening, so anyone who walks the
	-- bakery has to pass through them; nothing here ever opens or swings.
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

	-- Models that ARE the doorway rather than stand next to it, matched lowercased on the whole name.
	-- Every bakery gets this at boot, not only a claimed one: a shut front door blocks the map itself.
	-- Whole-name matching on purpose — the oven's OvenDoorLeft/Right must keep colliding.
	PassableModels = { "door" },
}

return Collision
