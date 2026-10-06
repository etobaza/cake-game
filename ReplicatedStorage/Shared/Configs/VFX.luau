--!strict
-- Authored particle roles, visibility limits and the complete dish presentation catalog.

--[[ Types ]]--
-- One emitter of a code-built burst. `From` clones an authored emitter ("Template/Parent/Emitter"
-- under `ReplicatedStorage.Assets.VFX`) so artist tuning such as flipbooks carries over; every other
-- field overrides that source or a fresh emitter.
export type EmitterSpec = {
	Name: string,
	From: string?,
	Count: number,
	Delay: number?,
	-- Attachment offset from the burst frame. `OnPart` emits from the template part's volume instead.
	Offset: Vector3?,
	OnPart: boolean?,
	Texture: string?,
	Color: ColorSequence?,
	Size: NumberSequence?,
	Transparency: NumberSequence?,
	Squash: NumberSequence?,
	Lifetime: NumberRange?,
	Speed: NumberRange?,
	Rotation: NumberRange?,
	RotSpeed: NumberRange?,
	SpreadAngle: Vector2?,
	Acceleration: Vector3?,
	Drag: number?,
	LightEmission: number?,
	LightInfluence: number?,
	Brightness: number?,
	ZOffset: number?,
	EmissionDirection: Enum.NormalId?,
	Shape: Enum.ParticleEmitterShape?,
	ShapeStyle: Enum.ParticleEmitterShapeStyle?,
	ShapeInOut: Enum.ParticleEmitterShapeInOut?,
}

export type ProceduralEffect = {
	-- Template part size; it bounds `OnPart` emission shapes.
	Size: Vector3?,
	Emitters: { EmitterSpec },
}

--[[ Constants ]]--
local GOLD = Color3.fromRGB(255, 214, 84)
local CREAM = Color3.fromRGB(255, 248, 225)
local PINK = Color3.fromRGB(255, 86, 120)
local YELLOW = Color3.fromRGB(255, 205, 60)
local CYAN = Color3.fromRGB(80, 200, 255)
local LIME = Color3.fromRGB(120, 230, 90)
local COIN_TEXTURE = "rbxassetid://100304091769166"
local STAR_TEXTURE = "rbxassetid://17062454177"
local CONFETTI_TEXTURE = "rbxassetid://137101016360901"
local STREAMER_TEXTURE = "rbxassetid://79682178388502"

--[[ Private Functions ]]--
local function key(time: number, value: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(time, value)
end

-- A light two-way squash reads as a tumbling coin; stronger values stretch it into a blade.
local COIN_SPIN = NumberSequence.new({
	key(0, 0),
	key(0.12, 0.45),
	key(0.25, -0.45),
	key(0.37, 0.45),
	key(0.5, -0.45),
	key(0.62, 0.45),
	key(0.75, -0.45),
	key(0.87, 0.45),
	key(1, 0),
})
-- A smaller two-way wobble makes paper flutter while it falls.
local FLUTTER = NumberSequence.new({
	key(0, 0),
	key(0.15, 1.2),
	key(0.3, -0.6),
	key(0.45, 1.2),
	key(0.6, -0.6),
	key(0.75, 1.2),
	key(0.9, -0.6),
	key(1, 0),
})
local FADE_OUT = NumberSequence.new({ key(0, 0), key(0.8, 0), key(1, 1) })

local function coins(count: number, speed: NumberRange): EmitterSpec
	return {
		Name = "Coins",
		Texture = COIN_TEXTURE,
		Count = count,
		Size = NumberSequence.new(0.55),
		Transparency = FADE_OUT,
		Squash = COIN_SPIN,
		Lifetime = NumberRange.new(0.75, 0.95),
		Speed = speed,
		SpreadAngle = Vector2.new(38, 38),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -42, 0),
		Rotation = NumberRange.new(-20, 20),
		LightInfluence = 0,
		Brightness = 1.2,
		ZOffset = 1,
	}
end

local function stars(count: number, speed: NumberRange, color: Color3): EmitterSpec
	return {
		Name = "Stars",
		Texture = STAR_TEXTURE,
		Count = count,
		Color = ColorSequence.new(CREAM, color),
		Size = NumberSequence.new({ key(0, 0), key(0.15, 0.75), key(1, 0) }),
		Lifetime = NumberRange.new(0.45, 0.85),
		Speed = speed,
		SpreadAngle = Vector2.new(75, 75),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -5, 0),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
		LightEmission = 0.6,
		LightInfluence = 0,
		Brightness = 3,
		ZOffset = 1.5,
	}
end

local function confetti(color: Color3, texture: string, count: number, offset: Vector3?, speed: NumberRange?): EmitterSpec
	return {
		Name = "Confetti",
		Texture = texture,
		Count = count,
		Offset = offset,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(0.38),
		Transparency = NumberSequence.new({ key(0, 0), key(0.85, 0), key(1, 1) }),
		Squash = FLUTTER,
		Lifetime = NumberRange.new(1.1, 1.6),
		Speed = speed or NumberRange.new(9, 15),
		SpreadAngle = Vector2.new(55, 55),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -10, 0),
		Drag = 2.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-320, 320),
		LightInfluence = 0.35,
		ZOffset = 0.5,
	}
end

-- Soft flash behind the burst, from the authored guest reaction glow.
local function glow(color: Color3, size: number, lifetime: number): EmitterSpec
	return {
		Name = "Glow",
		From = "Happy/Emoji/Glow",
		Count = 1,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ key(0, 0), key(0.18, size), key(1, 0) }),
		Transparency = NumberSequence.new({ key(0, 0.2), key(1, 1) }),
		Lifetime = NumberRange.new(lifetime),
		Brightness = 4,
		ZOffset = -0.5,
	}
end

-- Light rays from the authored reaction flare.
local function flare(color: Color3, size: number, lifetime: number): EmitterSpec
	return {
		Name = "Flare",
		From = "Happy/Emoji/Flare1",
		Count = 1,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ key(0, 0), key(0.2, size), key(1, 0) }),
		Transparency = NumberSequence.new({ key(0, 0.3), key(1, 1) }),
		Lifetime = NumberRange.new(lifetime),
		RotSpeed = NumberRange.new(60, 120),
		Brightness = 4,
		ZOffset = -0.4,
	}
end

-- The cartoon pop ring from the authored cleaning burst (a one-shot flipbook).
local function ring(color: Color3, size: number): EmitterSpec
	return {
		Name = "Ring",
		From = "Cleaning/Main/Circle2",
		Count = 1,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ key(0, 0), key(0.12, size * 0.55), key(1, size) }),
		Lifetime = NumberRange.new(0.32),
	}
end

--[[ Tables ]]--
local VFX = {
	Tag = "CakeVFXTarget",
	RoleAttribute = "VFXRole",
	ChoosingAttribute = "VFXChoosing",
	OffsetAttribute = "VFXOffset",
	SizeAttribute = "VFXSize",
	WaterUntilAttribute = "VFXWaterUntil",
	WaterStationAttribute = "VFXWaterStation",
	WaterTargetAttribute = "VFXWaterTarget",
	WaterFlightSeconds = 0.55,
	WaterGravity = Vector3.new(0, -12, 0),
	AssetTimeout = 10,
	Distance = 100,
	MaxBursts = 48,
	MaxEventAge = 2,
	MaxEmitterRate = 60,
	MaxEmitCount = 40,
	MaxLifetime = 10,
	MaxDelay = 5,
	-- Frame order follows tools and trays, avoiding one-frame separation from held props.
	RenderPriority = Enum.RenderPriority.Last.Value + 2,
	MinFoodScale = 0.15,
	MaxFoodScale = 1.5,
	PerfectFraction = 0.2,
	LateFraction = 0.8,
	SpeakingInterval = 2,
	SweepWait = 1,
	ReferenceRootHeight = 3,
	-- Normalized authored sweep cycle: each side fires once, even on a slow frame.
	SweepPhases = { { Group = "SweepLeft", Fraction = 0.2 }, { Group = "SweepRight", Fraction = 0.65 } },
	Effects = {
		Water = "Loop",
		Run = "Loop",
		Sweep = "Burst",
		Cleaning = "Burst",
		SpeakingIdle = "Repeat",
		Happy = "Burst",
		Singing = "Burst",
		Angry = "Burst",
		BlueberryCheesecake = "Loop",
		BerryCrumble = "Loop",
		ChocolatePancake = "Loop",
		ServePerfect = "Burst",
		ServeGreat = "Burst",
		ServeLate = "Burst",
		ServeSold = "Burst",
		StationReady = "Burst",
		LevelUp = "Burst",
		StreakBurst = "Burst",
	} :: { [string]: string },
	-- Bursts built in code from authored emitters and generated textures. An authored part with the
	-- same name in `Assets.VFX` takes precedence.
	Procedural = {
		ServePerfect = {
			Emitters = {
				glow(GOLD, 3.4, 0.5),
				flare(GOLD, 4.6, 0.6),
				ring(Color3.fromRGB(255, 236, 160), 3.2),
				stars(10, NumberRange.new(7, 12), GOLD),
				coins(7, NumberRange.new(12, 17)),
				confetti(PINK, CONFETTI_TEXTURE, 4),
				confetti(YELLOW, STREAMER_TEXTURE, 3),
				confetti(CYAN, CONFETTI_TEXTURE, 4),
				confetti(LIME, STREAMER_TEXTURE, 3),
			},
		},
		ServeGreat = {
			Emitters = {
				glow(CREAM, 2.6, 0.4),
				ring(CREAM, 2.6),
				stars(7, NumberRange.new(6, 10), Color3.fromRGB(170, 255, 140)),
				coins(5, NumberRange.new(11, 15)),
			},
		},
		ServeLate = {
			Emitters = { coins(3, NumberRange.new(9, 12)) },
		},
		ServeSold = {
			Emitters = {
				glow(Color3.fromRGB(190, 235, 255), 2.2, 0.35),
				stars(5, NumberRange.new(5, 8), Color3.fromRGB(150, 220, 255)),
				coins(4, NumberRange.new(10, 14)),
			},
		},
		StationReady = {
			Emitters = {
				glow(CREAM, 3, 0.45),
				ring(CREAM, 3),
				stars(9, NumberRange.new(5, 9), GOLD),
			},
		},
		LevelUp = {
			-- A column around the character: stars rise off its surface.
			Size = Vector3.new(4.5, 5.5, 4.5),
			Emitters = {
				flare(GOLD, 9, 0.8),
				glow(GOLD, 7, 0.6),
				ring(CREAM, 6),
				{
					Name = "Aura",
					Texture = STAR_TEXTURE,
					OnPart = true,
					Count = 26,
					Shape = Enum.ParticleEmitterShape.Cylinder,
					ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
					ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
					EmissionDirection = Enum.NormalId.Top,
					Color = ColorSequence.new(GOLD, CREAM),
					Size = NumberSequence.new({ key(0, 0), key(0.2, 0.6), key(1, 0) }),
					Lifetime = NumberRange.new(0.8, 1.4),
					Speed = NumberRange.new(1, 2),
					Acceleration = Vector3.new(0, 7, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-120, 120),
					LightEmission = 0.7,
					LightInfluence = 0,
					Brightness = 3,
					ZOffset = 1,
				},
				confetti(PINK, CONFETTI_TEXTURE, 6, Vector3.new(0, 2.5, 0), NumberRange.new(14, 20)),
				confetti(YELLOW, STREAMER_TEXTURE, 5, Vector3.new(0, 2.5, 0), NumberRange.new(14, 20)),
				confetti(CYAN, CONFETTI_TEXTURE, 6, Vector3.new(0, 2.5, 0), NumberRange.new(14, 20)),
				confetti(LIME, STREAMER_TEXTURE, 5, Vector3.new(0, 2.5, 0), NumberRange.new(14, 20)),
			},
		},
		StreakBurst = {
			-- Played at the character's feet: a ring of the oven's own flipbook fire flares up around them.
			Size = Vector3.new(4, 1, 4),
			Emitters = {
				{
					Name = "FireRing",
					From = "OvenFire/Fire1",
					OnPart = true,
					Count = 22,
					Shape = Enum.ParticleEmitterShape.Cylinder,
					ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
					ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
					EmissionDirection = Enum.NormalId.Top,
					Size = NumberSequence.new({ key(0, 0.6), key(0.3, 2.2), key(1, 1.2) }),
					Lifetime = NumberRange.new(0.6, 0.9),
					Speed = NumberRange.new(4, 7),
					Acceleration = Vector3.new(0, 6, 0),
					SpreadAngle = Vector2.new(15, 15),
				},
				{
					Name = "Embers",
					From = "OvenFire/Dots",
					Count = 24,
					Offset = Vector3.new(0, 0.3, 0),
					EmissionDirection = Enum.NormalId.Top,
					Speed = NumberRange.new(8, 14),
					SpreadAngle = Vector2.new(60, 60),
					Lifetime = NumberRange.new(0.6, 1.1),
				},
				flare(Color3.fromRGB(255, 120, 40), 7, 0.6),
				confetti(Color3.fromRGB(255, 70, 40), CONFETTI_TEXTURE, 6, Vector3.new(0, 5, 0), NumberRange.new(14, 20)),
				confetti(Color3.fromRGB(255, 150, 30), STREAMER_TEXTURE, 5, Vector3.new(0, 5, 0), NumberRange.new(14, 20)),
				confetti(Color3.fromRGB(255, 215, 60), CONFETTI_TEXTURE, 6, Vector3.new(0, 5, 0), NumberRange.new(14, 20)),
			},
		},
	} :: { [string]: ProceduralEffect },
	-- Studs above a station's prompt block where its ready burst plays.
	StationReadyLift = 0.6,
	FoodPresets = {
		bread = "BlueberryCheesecake",
		sweet_roll = "BlueberryCheesecake",
		marshmallow_twist = "BlueberryCheesecake",
		sweet_pretzel = "BlueberryCheesecake",
		chocolate_cookie = "ChocolatePancake",
		chocolate_croissant = "ChocolatePancake",
		strawberry_donut = "BerryCrumble",
		egg_benedict = "BlueberryCheesecake",
		cherry_jelly = "BerryCrumble",
		chocolate_strawberry = "ChocolatePancake",
		blueberry_bagel = "BerryCrumble",
		honey_taffy = "BlueberryCheesecake",
		berry_crumble = "BerryCrumble",
		raisin_bread = "BerryCrumble",
		apple_tart = "BerryCrumble",
		strawberry_scone = "BerryCrumble",
		chocolate_eclair = "ChocolatePancake",
		rainbow_lollipop = "BerryCrumble",
		carrot_granola_bar = "BerryCrumble",
		blueberry_cheesecake = "BlueberryCheesecake",
		grape_popsicle = "BerryCrumble",
		apple_strudel = "BerryCrumble",
		milk_chocolate = "ChocolatePancake",
		soft_serve = "BlueberryCheesecake",
		honey_cruller = "BlueberryCheesecake",
		caramel_flan = "BlueberryCheesecake",
		chocolate_pancake = "ChocolatePancake",
		carrot_pie = "BlueberryCheesecake",
		caramel_apple = "BerryCrumble",
		cherry_bundt_cake = "BerryCrumble",
		ice_cream_sandwich = "ChocolatePancake",
		red_velvet_cake = "BlueberryCheesecake",
		strawberry_ice_cream = "BerryCrumble",
		cherry_biscotti = "BerryCrumble",
		honey_macaron = "BlueberryCheesecake",
		lemon_sorbet = "BerryCrumble",
		carrot_cupcake = "BlueberryCheesecake",
		lemon_wafer = "BerryCrumble",
		lemon_meringue = "BerryCrumble",
		waffle_sundae = "ChocolatePancake",
		cherry_pie = "BerryCrumble",
		lemon_cake = "BerryCrumble",
		coffee = "BlueberryCheesecake",
	} :: { [string]: string },
}
return VFX
