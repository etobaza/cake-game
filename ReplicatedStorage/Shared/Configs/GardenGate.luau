--!strict
-- The boarded-up greenhouse arch. Until the owner buys something that lives in the greenhouse, the
-- kitchen's arch to it is nailed shut and a sign names the cheapest purchase that opens it.
-- GardenGateHandler builds the boards from these numbers; nothing is authored in the place.

--[[ Types ]]--
export type Board = {
	-- Centre in the gate frame (X across the opening, Y up from the floor, -Z towards the kitchen).
	Offset: Vector3,
	Size: Vector3,
	-- Roll around the gate's look axis, in degrees.
	Roll: number,
	Color: Color3,
}

--[[ Tables ]]--
local GardenGate = {
	Name = "GardenGate",

	-- The arch's floor centre on the template bakery (BaseConfig.TemplateName), looking from the
	-- garden into the kitchen. Measured on the kitchen Decoration "door" arch at template X 285.3:
	-- the opening is about 6.7 studs wide (template Z -326.1 to -319.4) and 8.5 tall above the floor.
	Template = CFrame.lookAt(Vector3.new(285.31, 1.2, -322.75), Vector3.new(284.31, 1.2, -322.75)),

	-- Invisible wall filling the opening. It sits in a folder named like the room's wall folders
	-- (Collision.WallFolders), so garden prompts do not reach through it either.
	Blocker = {
		Offset = Vector3.new(0, 4.6, 0),
		Size = Vector3.new(7, 9.2, 1),
	},

	Material = Enum.Material.Wood,
	Boards = {
		{ Offset = Vector3.new(0, 1.7, -1.5), Size = Vector3.new(7.6, 0.9, 0.25), Roll = 3, Color = Color3.fromRGB(133, 92, 58) },
		{ Offset = Vector3.new(0, 3.9, -1.5), Size = Vector3.new(7.8, 0.9, 0.25), Roll = -4, Color = Color3.fromRGB(116, 79, 49) },
		{ Offset = Vector3.new(0, 6.6, -1.5), Size = Vector3.new(7.6, 0.9, 0.25), Roll = 5, Color = Color3.fromRGB(140, 98, 62) },
		{ Offset = Vector3.new(0, 8.7, -1.5), Size = Vector3.new(7.2, 0.9, 0.25), Roll = -2, Color = Color3.fromRGB(121, 83, 52) },
		{ Offset = Vector3.new(0, 4.6, -1.8), Size = Vector3.new(10.4, 0.85, 0.25), Roll = 52, Color = Color3.fromRGB(105, 71, 44) },
		{ Offset = Vector3.new(0, 4.6, -1.8), Size = Vector3.new(10.4, 0.85, 0.25), Roll = -52, Color = Color3.fromRGB(111, 75, 47) },
	} :: { Board },

	-- The board naming what opens the greenhouse, nailed over the crossing planks.
	Sign = {
		Offset = Vector3.new(0, 5.4, -2.05),
		Size = Vector3.new(5, 2.6, 0.2),
		Color = Color3.fromRGB(222, 184, 135),
		TextColor = Color3.fromRGB(74, 45, 24),
		Font = Enum.Font.FredokaOne,
		PixelsPerStud = 50,
	},
}

return GardenGate
