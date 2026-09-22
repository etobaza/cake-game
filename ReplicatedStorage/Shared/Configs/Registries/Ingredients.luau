--!strict
-- Ingredient registry: where it comes from, how much it produces and what it means for menu tags.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Registry = require(_Shared.Registry)

export type IngredientSource = "Infinite" | "Plot" | "Tree" | "Animal"

-- The authored shape; Registry.Build stamps `id` onto every entry.
type IngredientDefinition = {
	name: string,
	source: IngredientSource,
	-- Animal product: a dish containing it is not vegan.
	animal: boolean?,
	gluten: boolean?,
	-- Seconds to ripen after watering / feeding. Not set for Infinite ones.
	produceSeconds: number?,
	-- Hotbar art. Until it is filled in the slot shows the name alone.
	icon: string?,
}
export type IngredientEntry = IngredientDefinition & { id: string }

local list: { [string]: IngredientDefinition } = {
	flour = {
		name = "Flour",
		source = "Infinite",
		gluten = true,
	},
	sugar = {
		name = "Sugar",
		source = "Infinite",
	},

	strawberry = {
		name = "Strawberry",
		source = "Plot",
		produceSeconds = 90,
	},
	blueberry = {
		name = "Blueberry",
		source = "Plot",
		produceSeconds = 110,
	},
	grape = {
		name = "Grape",
		source = "Plot",
		produceSeconds = 130,
	},
	carrot = {
		name = "Carrot",
		source = "Plot",
		produceSeconds = 150,
	},
	apple = {
		name = "Apple",
		source = "Tree",
		produceSeconds = 130,
	},
	lemon = {
		name = "Lemon",
		source = "Tree",
		produceSeconds = 140,
	},
	cherry = {
		name = "Cherry",
		source = "Tree",
		produceSeconds = 120,
	},
	cocoa = {
		name = "Cocoa",
		source = "Tree",
		produceSeconds = 160,
	},

	egg = {
		name = "Egg",
		source = "Animal",
		animal = true,
		produceSeconds = 100,
	},
	milk = {
		name = "Milk",
		source = "Animal",
		animal = true,
		produceSeconds = 140,
	},
	honey = {
		name = "Honey",
		source = "Animal",
		animal = true,
		produceSeconds = 180,
	},
}

type IngredientsMethods = {
	IsInfinite: (self: IngredientsRegistry, ingredientId: string) -> boolean,
}
export type IngredientsRegistry = Registry.Registry<IngredientEntry> & IngredientsMethods

local methods: IngredientsMethods = {
	-- Infinite ingredients are not stored in the pantry and are never spent.
	IsInfinite = function(self: IngredientsRegistry, ingredientId: string): boolean
		local entry = self:Get(ingredientId)
		return entry ~= nil and entry.source == "Infinite"
	end,
}

local IngredientsRegistry: IngredientsRegistry = Registry.Build("Ingredients", list, methods)

return IngredientsRegistry
