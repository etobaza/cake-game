--!strict
-- Single shared contract for the cooking/entrance motion visuals: the CollectionService tags, the
-- server-authored metadata attribute names, and all client-side visual tuning. The server handlers
-- author the metadata; this config keeps both sides agreeing on names so nothing is duplicated.

--[[ Modules ]]
--
local FoodPresentation = require(script.Parent.FoodPresentation)
local Sounds = require(script.Parent.Sounds)

--[[ Constants ]]
--
-- Fixed tag contract. A cooking surface is a server Folder named Food_<buildingId> holding server
-- food Models; the other three tags sit on a single BasePart or Model each.
local CookingMotion = {
	SurfaceTag = "CookingSurface",
	FreshTag = "FreshCookedFood",
	ClockTag = "OvenClockMotion",
	EntranceTag = "BakeryEntranceMotion",

	-- Beyond this distance from the camera an entry pauses its animation and restores the source.
	CullDistance = 140,

	-- Station states shared by the surface and the oven clock metadata.
	State = {
		Mixing = "Mixing",
		Cooking = "Cooking",
		Ready = "Ready",
		Burnt = "Burnt",
	},

	-- The entrance chime plays the DoorBell entry of Configs/Sounds.
	ChimeSound = "DoorBell" :: Sounds.SoundName,
}

-- Station timing attributes the server's CookingMetadata replicates onto both the oven clock hand
-- and a mixer surface folder. The per-target tables below reuse these names.
local Station = {
	StationState = "StationState",
	PhaseStartedAt = "PhaseStartedAt",
	ReadyAt = "ReadyAt",
	BurnAt = "BurnAt",
	HeatPausedAt = "HeatPausedAt",
	PausedAt = "PausedAt",
}
CookingMotion.Station = Station

-- Cooking surface (Food_<buildingId>) folder attributes.
CookingMotion.Surface = {
	StationKind = "StationKind",
	StationState = Station.StationState,
	RecipeId = "RecipeId",
	SurfaceFrame = "SurfaceFrame",
	BatterColor = "BatterColor",
	-- Authoritative mixing window, retained through Ready; summary resume shifts both together.
	MixStartedAt = "MixStartedAt",
	MixReadyAt = "MixReadyAt",
	PausedAt = Station.PausedAt,
	HeatPausedAt = Station.HeatPausedAt,
}

-- Ingredient Model attributes inside a surface folder.
CookingMotion.Ingredient = {
	IngredientId = "IngredientId",
	PortionIndex = "PortionIndex",
}

-- Fresh completion Model attributes, tagged only on a real Mixing/Cooking -> Ready transition.
CookingMotion.Fresh = {
	CompletedAt = "CompletedAt",
	CompletionFrame = "CompletionFrame",
	FoodKind = "FoodKind",
	RecipeId = "RecipeId",
}

-- Oven ClockHand BasePart metadata.
CookingMotion.Clock = {
	RestPivot = "ClockRestPivot",
	Axis = "ClockAxis",
	StationState = Station.StationState,
	PhaseStartedAt = Station.PhaseStartedAt,
	ReadyAt = Station.ReadyAt,
	BurnAt = Station.BurnAt,
	HeatPausedAt = Station.HeatPausedAt,
	PausedAt = Station.PausedAt,
}

-- Entrance leaf Model metadata. Sign attributes are present only on the leaf that owns the sign.
CookingMotion.Entrance = {
	HingePosition = "EntranceHingePosition",
	ClosedPivot = "EntranceClosedPivot",
	OpenPivot = "EntranceOpenPivot",
	CafeOpen = "CafeOpen",
	SignClosedLocal = "SignClosedLocal",
	SignOpenLocal = "SignOpenLocal",
}

--[[ Mixer tuning ]]
--
-- Matches the authored bowl slots: radius 0.8, slot lift 0.12, max portion 1.1 x 0.9 x 1.1, four
-- portions. The dough is one pastry mesh that grows as the batter blends. A batch with more portions
-- than slots keeps the static server pieces instead of swirling.
CookingMotion.Mixer = {
	SlotCount = 4,
	SlotRadius = 0.8,
	SlotHeight = 0.12,
	PortionSize = Vector3.new(1.1, 0.9, 1.1),
	-- Full dough footprint. It is the server's Ready dough size on a station surface, so the server
	-- result takes over from the local dough without a size pop.
	DoughMaxSize = FoodPresentation.SurfaceFoodSize,
	DoughMinScale = 0.12,
	-- Continuous swirl: the orbit angle follows mixing progress so Summary freezes it exactly.
	SwirlRevolutions = 2.25,
	-- Convergence begins past this progress; before it the ingredients simply swirl at the rim.
	ConvergeStart = 0.5,
	-- Rim radius collapses to this fraction as the ingredients gather over the dough.
	ConvergeRadiusFraction = 0.12,
	-- The converged clones fade out across this tail so only the blended dough remains at Ready.
	BlendFadeStart = 0.85,
	BobHeight = 0.04,
	ConvergedScale = 0.4,
	-- Warm cream batter when the folder has no authored BatterColor yet.
	DefaultBatterColor = Color3.fromRGB(255, 244, 216),
}

--[[ Fresh food tuning ]]
--
CookingMotion.FreshFood = {
	-- One-shot ready squash for both dough and dishes; FreshFood owns it so two layers never fight.
	SquashSeconds = 0.45,
	SquashAmplitude = 0.14,
	-- A completion older than this on first binding is a rebind or a moved dish: never replay it.
	MaxBindAge = 0.7,
	HopHeight = 0.12,
	DishStartScale = 0.9,
	AppearFraction = 0.18,
}

--[[ Entrance tuning ]]
--
-- Spring stiffness/damping give a damping ratio near 0.79: under ~2% overshoot and a ~0.65 s settle.
CookingMotion.EntranceMotion = {
	SpringStiffness = 62,
	SpringDamping = 12.5,
	-- A long frame must not make the spring ring; clamp dt before integrating.
	MaxStepSeconds = 1 / 30,
	-- Quiet positional chime a beat after the leaf starts opening.
	ChimeDelay = 0.12,
	ChimePlaybackSpeed = 1,
}

export type CookingMotion = typeof(CookingMotion)

return CookingMotion
