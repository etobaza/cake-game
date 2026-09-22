--!strict
-- Customer type registry: patience, tips, how many dishes they order and from which level they show up.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local GameTypes = require(_Shared.GameTypes)
local Registry = require(_Shared.Registry)

-- The authored shape; Registry.Build stamps `id` onto every entry.
type CustomerTypeDefinition = {
	name: string,
	kind: GameTypes.CustomerKind,
	-- Seconds of patience from arrival to leaving. A seated order is a mix plus a bake plus two walks,
	-- and the walk is across the whole room: these are written so a dish can be cooked from scratch
	-- after the order lands, not only handed over from a stocked display.
	patience: number,
	tipMultiplier: number,
	orders: number,
	-- Weight in the random pick among available types.
	weight: number,
	unlockLevel: number,
	-- Colour of the guest body in the world; the type is recognised across the room by it.
	color: Color3,
}
export type CustomerTypeEntry = CustomerTypeDefinition & { id: string }

local list: { [string]: CustomerTypeDefinition } = {
	regular = {
		name = "Regular",
		kind = "Seated",
		patience = 160,
		tipMultiplier = 1,
		orders = 1,
		weight = 10,
		unlockLevel = 1,
		color = Color3.fromRGB(226, 178, 148),
	},
	browser = {
		name = "Window Shopper",
		kind = "Display",
		patience = 70,
		tipMultiplier = 0,
		orders = 0,
		weight = 6,
		unlockLevel = 1,
		color = Color3.fromRGB(168, 202, 224),
	},
	family = {
		name = "Family",
		kind = "Seated",
		patience = 190,
		tipMultiplier = 1.4,
		orders = 1,
		weight = 4,
		unlockLevel = 8,
		color = Color3.fromRGB(196, 214, 152),
	},
	big_order = {
		name = "Double Order",
		kind = "Seated",
		patience = 190,
		tipMultiplier = 1.5,
		orders = 2,
		weight = 3,
		unlockLevel = 11,
		color = Color3.fromRGB(222, 186, 232),
	},
	critic = {
		name = "Critic",
		kind = "Seated",
		patience = 100,
		tipMultiplier = 2.2,
		orders = 1,
		weight = 2,
		unlockLevel = 14,
		color = Color3.fromRGB(148, 146, 166),
	},
}

type CustomerTypesMethods = {
	GetAvailable: (self: CustomerTypesRegistry, level: number) -> { CustomerTypeEntry },
}
export type CustomerTypesRegistry = Registry.Registry<CustomerTypeEntry> & CustomerTypesMethods

local methods: CustomerTypesMethods = {
	-- Types available to the player at their level. Coffee is ordered by regulars if it is on the day menu.
	GetAvailable = function(self: CustomerTypesRegistry, level: number): { CustomerTypeEntry }
		return self:Query()
			:Where(function(entry: CustomerTypeEntry)
				return entry.unlockLevel <= level
			end)
			:ToArray()
	end,
}

local CustomerTypesRegistry: CustomerTypesRegistry = Registry.Build("CustomerTypes", list, methods)

return CustomerTypesRegistry
