--!strict
-- Base buildings: how they look, how many there are and which class runs them.
-- Where they stand is the reference bakery's Anchors folder (see Configs/Base): a part named after
-- the building id, mapped into each bakery by BaseHandler's transform.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Base = require(script.Parent.Base)

--[[ Tables ]]--
-- Real models instead of the placeholder block. Model is a path inside the room template;
-- Asset is a name under ReplicatedStorage.Assets.Models (folders allowed).
export type Furniture = {
	Model: { string }?,
	Asset: string?,
	-- Unwatered tree: a second clone named Dry, swapped by the client.
	DryAsset: string?,
	-- Chair model and its spots around the building, in the building's own space.
	-- The first spot is the one a guest is put into, the rest are there to make the table look used.
	Chair: { string }?,
	Chairs: { Vector3 }?,
	-- Turn of the chairs, in degrees. A chair is aimed at the table by its mesh part; set this if that
	-- mesh is modelled facing sideways or backwards and the guests end up sitting the wrong way.
	ChairYaw: number?,
	-- Height of the seat above the floor inside the chair model.
	SeatLift: number?,
	-- Artist copies near this building: only those come down, extras stay until their slot spawns.
	Clear: { { string } }?,
}

export type Single = {
	Id: string,
	Furniture: Furniture?,
	-- Authored model this building lives on, as a path from the bakery root. Overrides the kind's own.
	WorldModel: { string }?,
}

export type Kind = {
	-- Which behavior class BuildingHandler builds. Prop is a view with no state.
	Class: string,
	-- Which prompt view the client draws. Defaults to Class.
	View: string?,
	-- Optional physical state view owned by Building (for example, the authored oven doors and dial).
	Visual: string?,
	Size: Vector3,
	Color: Color3,
	Label: string,
	Facing: Vector3,
	-- Group building: Stat decides how many exist, slot N is the anchor `<Prefix>_N`.
	Prefix: string?,
	Stat: string?,
	RequiredUpgrade: string?,
	-- Which anchor each purchase fills, when the shop order is not the anchor order: purchase N goes
	-- to anchor `SlotOrder[N]`. Missing means purchase N fills anchor N.
	SlotOrder: { number }?,
	-- One-off buildings with their own ids. Each id is an anchor.
	Singles: { Single }?,
	-- An invisible point in the world: no label, no prompt, no collisions.
	Marker: boolean?,
	-- Invisible block that keeps its prompt: the look comes from a model the artist already drew in
	-- the bakery, the block only carries the interaction.
	Hidden: boolean?,
	-- Vertical offset of the custom prompt from the building centre. Missing keeps the usual spot
	-- above the building; zero puts it in the middle of an invisible interaction volume.
	PromptLift: number?,
	-- Authored model whose bounding-box centre carries the prompt. The path is relative to the
	-- bakery root and takes priority over PromptLift.
	PromptTarget: { string }?,
	-- Camera-space adjustment measured in fractions of the prompt's own width and height.
	PromptScreenOffset: Vector2?,
	-- The artist model this kind lives on, as a path from the bakery root. Nothing is built for it:
	-- the authored model IS the building, so it carries the prompt and it is what hides while a tool
	-- is carried. A Single may name its own instead.
	WorldModel: { string }?,
	-- Real models per slot index, for groups whose members look different (crops, trees).
	FurnitureByIndex: { [number]: Furniture }?,
	-- Hands item this rack gives. The world mesh hides while that item is held.
	ToolId: string?,
	-- The woodpile hands out one log per visit. Each log refreshes the oven's timed fire.
	GivesFuel: boolean?,
	-- Hotbar art of the tool this rack gives. Until it is filled in the slot shows the name alone.
	Icon: string?,
	-- Held copy: scale of the world mesh and where it sits on the R6 right arm.
	HeldScale: number?,
	Grip: CFrame?,
	-- Asset the held copy is cloned from, when the kind spawns no furniture of its own to clone.
	HeldAsset: string?,
	-- Where the hand grips the shaft, as a fraction of the mesh height measured from its centre and
	-- counted downwards. A long mop has to be gripped above its centre (a negative value) or the head
	-- sinks through the floor. Missing means the default in HandsHandler.
	GripAlong: number?,
	-- Real models standing in place of the block. The block stays as the anchor of the prompt.
	Furniture: Furniture?,
	-- GuestSeat1/2 attachments on the reference anchor place runtime seats in authored chairs.
	SeatsFromAnchors: boolean?,
	-- Station rules. Firewood burns over time, food burns after the heated ready window, a mixing station
	-- starts recipes instead of finishing them.
	UsesFuel: boolean?,
	Burns: boolean?,
	Mixes: boolean?,
	-- Keep the station usable without a valid batch, explaining the missing input through server refusals.
	LoadFeedback: { Missing: string, WrongRecipe: string }?,
	-- Session field holding the state of this kind, e.g. Stations or Tables.
	StateField: string?,
	-- Garden rules: where the nodes live in the save, which field marks the care and the produce list.
	Group: string?,
	CareField: string?,
	Produce: string?,
	-- Label of the care action, also picks the packet the client fires.
	CareAction: string?,
	-- Stat that takes the care over on a new day. Missing means it is always done by hand.
	AutoCareStat: string?,
	-- Tool the player must hold to tend this node: the watering can, the hay.
	CareTool: string?,
}

local Buildings = {
	Tag = "BaseProp",
	IdAttribute = "PropId",
	KindAttribute = "PropKind",
	-- Hands id of one log. Logs are all alike, so there is no registry row for them.
	FuelItemId = "firewood",
	HarvestAttribute = "HarvestBit",
	LiveModelName = "Live",
	DryModelName = "Dry",

	-- Kitchen stands outside, past spawn. Cafe and garden stay inside. Layout is the Anchors folder.
	Kinds = {
		Mixer = {
			Class = "Station",
			Size = Vector3.new(3, 3, 2.5),
			Color = Color3.fromRGB(214, 200, 180),
			Label = "Mixer",
			Facing = Vector3.new(1, 0, 0),
			Prefix = "mixer",
			Stat = "MixerCount",
			StateField = "Stations",
			Mixes = true,
			-- The mixing bowl the artist drew on the counter (their name for it is `Circle`):
			-- ingredients go into that, not into a block of ours standing beside it.
			WorldModel = { "1ndFloor", "Kitchen", "Decoration", "KitchenCounter", "Circle" },
		},
		Oven = {
			Class = "Station",
			Visual = "Oven",
			Size = Vector3.new(3.5, 3.5, 3),
			Color = Color3.fromRGB(120, 82, 62),
			Label = "Oven",
			Facing = Vector3.new(1, 0, 0),
			Prefix = "oven",
			Stat = "OvenCount",
			StateField = "Stations",
			UsesFuel = true,
			Burns = true,
			-- No model of our own: the artist authored the brick oven at oven_1 and the two upgrade
			-- ovens in the Kitchen `Upgrades` folder. Spawning ours put a second oven inside theirs.
			Hidden = true,
		},
		Freezer = {
			Class = "Station",
			Size = Vector3.new(2.5, 3.5, 2.5),
			Color = Color3.fromRGB(160, 205, 220),
			Label = "Freezer",
			Facing = Vector3.new(1, 0, 0),
			Prefix = "freezer",
			Stat = "FreezerCount",
			StateField = "Stations",
			LoadFeedback = { Missing = "need_frozen_mix", WrongRecipe = "wrong_frozen_mix" },
			Hidden = true,
		},
		Coffee = {
			Class = "Station",
			Size = Vector3.new(2.5, 3, 2),
			Color = Color3.fromRGB(90, 70, 60),
			Label = "Coffee machine",
			Facing = Vector3.new(1, 0, 0),
			Prefix = "coffee",
			Stat = "CoffeeCount",
			StateField = "Stations",
			Hidden = true,
		},
		Display = {
			Class = "DisplaySlot",
			Size = Vector3.new(2.5, 2.5, 2.5),
			Color = Color3.fromRGB(240, 220, 170),
			Label = "Display",
			Facing = Vector3.new(1, 0, 0),
			Prefix = "display",
			Stat = "DisplaySlots",
			StateField = "Display",
			Hidden = true,
		},
		Table = {
			Class = "CafeTable",
			Visual = "TableMenus",
			-- Invisible under the model: the height only decides where the label hangs.
			Size = Vector3.new(5, 5, 5),
			Color = Color3.fromRGB(190, 150, 110),
			Label = "Table",
			-- Facing runs toward the doorway, so the guest chair is on the side they come from.
			Facing = Vector3.new(0, 0, 1),
			Prefix = "table",
			Stat = "TableCount",
			StateField = "Tables",
			-- The artist laid both cafe tables out by hand, complete with chairs, cups and menus, so
			-- nothing is spawned here: the block only carries the prompt and the guest's seat.
			Hidden = true,
			-- The first table owned is the one drawn in Decoration (anchor 2); the one the upgrade
			-- pays for is drawn in the Cafe `Upgrades` folder (anchor 1).
			SlotOrder = { 2, 1 },
			SeatsFromAnchors = true,
		},
		Plot = {
			Class = "GardenNode",
			Size = Vector3.new(4, 2, 4),
			Color = Color3.fromRGB(110, 84, 56),
			Label = "Garden plot",
			Facing = Vector3.new(-1, 0, 0),
			Prefix = "plot",
			Stat = "PlotCount",
			Group = "Plots",
			CareField = "Watered",
			Produce = "PlotCrops",
			CareAction = "Water",
			AutoCareStat = "AutoWater",
			CareTool = "watering_can",
			Hidden = true,
		},
		Tree = {
			Class = "GardenNode",
			Size = Vector3.new(5, 8, 5),
			Color = Color3.fromRGB(96, 138, 72),
			Label = "Fruit tree",
			Facing = Vector3.new(-1, 0, 0),
			Prefix = "tree",
			Stat = "TreeCount",
			-- Shop order is cocoa, cherry, apple, lemon; the artist's trees stand apple, cherry,
			-- lemon, cocoa. Each purchase goes to the anchor its own species was drawn at.
			SlotOrder = { 4, 2, 1, 3 },
			Group = "Trees",
			CareField = "Watered",
			Produce = "TreeCrops",
			CareAction = "Water",
			AutoCareStat = "AutoWater",
			CareTool = "watering_can",
			Hidden = true,
		},
		Animal = {
			Class = "GardenNode",
			Size = Vector3.new(3, 3, 3.5),
			Color = Color3.fromRGB(235, 235, 225),
			Label = "Animal",
			Facing = Vector3.new(-1, 0, 0),
			Prefix = "animal",
			Stat = "AnimalCount",
			-- Chickens are bought first but the artist drew the cow at animal_1.
			SlotOrder = { 2, 1, 3 },
			Group = "Animals",
			CareField = "Fed",
			Produce = "AnimalProduce",
			CareAction = "Brush",
			-- The chicken coop, the cow and the hive are the artist's upgrade models shown by
			-- UpgradeViewHandler; the node block only carries the feed/harvest prompt.
			Hidden = true,
		},
		RailCart = {
			Class = "RailCart",
			Visual = "RailCart",
			Hidden = true,
			Size = Vector3.new(3, 3, 3),
			Color = Color3.fromRGB(140, 105, 65),
			Label = "Rail cart",
			Facing = Vector3.new(0, 0, 1),
			RequiredUpgrade = "garden_cart",
			Singles = { { Id = "rail_cart" } },
		},
		RailOutput = {
			Class = "Prop",
			View = "RailCart",
			Hidden = true,
			Size = Vector3.new(3, 3, 3),
			Color = Color3.fromRGB(140, 105, 65),
			Label = "Deliveries",
			Facing = Vector3.new(0, 0, 1),
			RequiredUpgrade = "garden_cart",
			Singles = {
				{ Id = "rail_output" },
				{ Id = "rail_output_2" },
				{ Id = "rail_output_3" },
				{ Id = "rail_output_4" },
			},
		},
		Fuel = {
			Class = "Prop",
			View = "FuelPile",
			Size = Vector3.new(3, 2.5, 3),
			Color = Color3.fromRGB(140, 105, 65),
			Label = "Firewood",
			Facing = Vector3.new(1, 0, 0),
			-- The artist's woodpile already stands on this anchor (Kitchen Upgrades/FireWood).
			Hidden = true,
			GivesFuel = true,
			Singles = { { Id = "fuel" } },
		},
		Trash = {
			Class = "Prop",
			View = "TrashBin",
			Visual = "Trash",
			Size = Vector3.new(5, 6, 5),
			Color = Color3.fromRGB(90, 95, 100),
			Label = "Trash",
			Facing = Vector3.new(0, 0, 1),
			-- The usable bin is the artist's can beside the broom, not a spawned replacement.
			WorldModel = { "1ndFloor", "Kitchen", "Decoration", "Cube.006" },
			Singles = { { Id = "trash" } },
		},
		Broom = {
			Class = "Prop",
			View = "ToolRack",
			Size = Vector3.new(1, 4, 1),
			Color = Color3.fromRGB(140, 105, 65),
			Label = "Broom",
			Facing = Vector3.new(0, 0, -1),
			ToolId = "broom",
			-- Nothing is spawned here: the broom on the kitchen floor is the one the artist drew, and
			-- the block beside it only carries the prompt. Taking the broom hides that model.
			Hidden = true,
			WorldModel = { "1ndFloor", "Kitchen", "Decoration", "BROOM" },
			-- Exact tool geometry and hand attachment from Workspace.broom's animation rig.
			HeldAsset = "AnimationBroom",
			Singles = { { Id = "broom" } },
		},
		WateringCan = {
			Class = "Prop",
			View = "ToolRack",
			Size = Vector3.new(1.5, 2.5, 1.5),
			Color = Color3.fromRGB(120, 160, 175),
			Label = "Watering can",
			Facing = Vector3.new(0, 0, -1),
			ToolId = "watering_can",
			-- The can stays at the artist's sink, independently of the Crystal Water upgrade.
			WorldModel = { "1ndFloor", "Garden", "Decoration", "WateringCan" },
			-- The hold clip was authored with this mesh and its RightHand motor offset.
			HeldAsset = "AnimationWateringCan",
			Singles = { { Id = "watering_can" } },
		},
		Hay = {
			Class = "Prop",
			View = "ToolRack",
			Size = Vector3.new(2.5, 2, 2.5),
			Color = Color3.fromRGB(214, 176, 92),
			Label = "Hay",
			Facing = Vector3.new(0, 0, -1),
			ToolId = "hay",
			HeldScale = 0.5,
			Grip = CFrame.new(),
			Furniture = { Asset = "Hay" },
			Singles = {},
		},
		Ingredient = {
			Class = "Prop",
			View = "Dispenser",
			Size = Vector3.new(1.5, 3, 1.5),
			Color = Color3.fromRGB(206, 174, 122),
			Label = "Ingredient",
			Facing = Vector3.new(0, 0, 1),
			Prefix = "ingredient",
			-- The pantry is the two trays the artist drew on the kitchen counter, and nothing else:
			-- milk and eggs use the animal-owned kitchen baskets in Configs/Garden instead.
			-- Both staple trays are authored models -- no block of ours is built for them.
			-- Artist names, not ours: the sugar cubes were modelled as `Cheese` (four of them, all in the
			-- left tray, so any one of them is that tray) and the flour sack in the right tray as `Bag`.
			Singles = {
				{
					Id = "ingredient_sugar",
					WorldModel = { "1ndFloor", "Kitchen", "Decoration", "KitchenCounter", "Cheese" },
				},
				{
					Id = "ingredient_flour",
					WorldModel = { "1ndFloor", "Kitchen", "Decoration", "KitchenCounter", "Bag" },
				},
			},
		},
		Door = {
			Class = "Prop",
			View = "Door",
			-- A full-height invisible volume keeps its bottom on the navigation anchor while putting
			-- the prompt in the centre between the two authored entrance leaves.
			Size = Vector3.new(6, 6, 1),
			Color = Color3.new(1, 1, 1),
			Label = "Entrance",
			-- Faces OUTWARDS: the guide uses this direction to tell whether the player is inside yet.
			Facing = Vector3.new(0, 0, 1),
			Hidden = true,
			PromptLift = 0,
			PromptTarget = { "1ndFloor", " exterior", "Door" },
			PromptScreenOffset = Vector2.new(0.35, 0),
			Singles = { { Id = "door" } },
		},
		-- World dressing is authored straight into each bakery. This kind stays for leftover markers.
		Decor = {
			Class = "Prop",
			Size = Vector3.new(1, 1, 1),
			Color = Color3.new(1, 1, 1),
			Label = "Decor",
			Facing = Vector3.new(0, 0, 1),
			Marker = true,
			Singles = {},
		},
		-- Spawned by CleaningHandler during a shift, not by BuildingHandler.
		Spill = {
			Class = "Prop",
			View = "Spill",
			Size = Vector3.new(4, 0.2, 4),
			Color = Color3.fromRGB(90, 70, 40),
			Label = "Spill",
			Facing = Vector3.new(0, 0, 1),
		},
	} :: { [string]: Kind },
}

--[[ Handling ]]--
-- Building ids are `<prefix>_<number>`; one-off buildings have no number and read as 0.
function Buildings.GetIndex(buildingId: string): number
	return tonumber(string.match(buildingId, "_(%d+)$")) or 0
end

function Buildings.GetId(kindName: string, index: number): string
	return `{Buildings.Kinds[kindName].Prefix}_{index}`
end

-- Hands item a tool rack gives, or nil if this building is not a rack.
function Buildings.GetToolId(buildingId: string): string?
	for _, kind in Buildings.Kinds do
		if kind.ToolId then
			for _, single in (kind.Singles or {}) :: { Single } do
				if single.Id == buildingId then
					return kind.ToolId
				end
			end
		end
	end

	return nil
end

-- The woodpile kind, and whether a building id is that pile. Both read the registry flag rather than
-- the kind name, so moving the logs onto another building is one flag.
function Buildings.FuelPileKind(): Kind?
	for _, kind in Buildings.Kinds do
		if kind.GivesFuel then
			return kind
		end
	end

	return nil
end

function Buildings.GivesFuel(buildingId: string): boolean
	local kind = Buildings.FuelPileKind()

	for _, single in ((kind and kind.Singles) or {}) :: { Single } do
		if single.Id == buildingId then
			return true
		end
	end

	return false
end

-- Label of a carried log, from the pile that hands it out.
function Buildings.FuelLabel(): string
	local kind = Buildings.FuelPileKind()

	return if kind then kind.Label else Buildings.FuelItemId
end

-- Label of a held tool, from the rack that gives it.
function Buildings.ToolLabel(toolId: string): string
	local kind = Buildings.KindForTool(toolId)

	return if kind then kind.Label else toolId
end

function Buildings.KindForTool(toolId: string): Kind?
	for _, kind in Buildings.Kinds do
		if kind.ToolId == toolId then
			return kind
		end
	end

	return nil
end

-- Walks a name path from a bakery (or a room) down to the instance it addresses.
function Buildings.ResolvePath(root: Instance, path: { string }): Instance?
	local current: Instance? = root

	for _, name in path do
		current = current and current:FindFirstChild(name)
	end

	return current
end

-- The artist model a kind lives on, found from the part that carries its prompt. The server hides it
-- while a tool is carried and the guide lights it up. Nil when the kind builds its own block -- then
-- that block is the thing, and the part passed in already is it.
function Buildings.WorldModel(part: BasePart): Instance?
	local kindName = part:GetAttribute(Buildings.KindAttribute)
	local kind = if typeof(kindName) == "string" then Buildings.Kinds[kindName] else nil
	local path = kind and kind.WorldModel
	local propId = part:GetAttribute(Buildings.IdAttribute)
	for _, single in ((kind and kind.Singles) or {}) :: { Single } do
		if single.Id == propId and single.WorldModel then
			path = single.WorldModel
			break
		end
	end
	if not path then
		return nil
	end

	-- The part hangs somewhere under its bakery; the path is written from the bakery root.
	local bakery: Instance = part
	while bakery.Parent and bakery.Parent.Name ~= Base.BakeriesFolderName do
		bakery = bakery.Parent
	end

	return if bakery.Parent then Buildings.ResolvePath(bakery, path) else nil
end

-- Clone source for Furniture.Asset. Looks in Models and its folders, not inside Room1.
function Buildings.FindAsset(assetName: string): Instance?
	local models = ReplicatedStorage.Assets.Models

	for _, child in models:GetChildren() do
		if child.Name == assetName then
			return child
		end

		if child:IsA("Folder") then
			local inst = child:FindFirstChild(assetName)
			if inst then
				return inst
			end
		end
	end

	return nil
end

return Buildings
