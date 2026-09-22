--!strict
-- What a building view gets and what it returns.
-- The context is built by InteractHandler: views read state through it and never touch handlers.

--[[ Tables ]]--
local Types = {}

export type PromptState = {
	Label: string,
	Action: string?,
	Fire: (() -> ())?,
	-- Colour the building takes while it is in this state; nil keeps its own colour. See Tints.
	Tint: Color3?,
}

export type Context = {
	PropId: string,
	Kind: string,
	AnimalAction: string?,
	-- Number at the end of the id: slot, plot or station number. 0 for one-off buildings.
	Index: number,
	-- Replicated session field by name, nil until the data arrives.
	Session: (key: string) -> any?,
	-- Replicated cloud value by path, e.g. Cloud({ "Garden", "Plots" }).
	Cloud: (path: { string }) -> any?,
	-- Last item in the player's hands.
	Held: () -> any?,
	RecipeName: (recipeId: string?) -> string,
	ItemName: (item: any) -> string,
	-- Whole seconds left until a deadline, never below zero.
	Seconds: (deadline: number) -> number,
}

-- One building view module: Describe is required, Paint is an optional per-part refresh.
export type View = {
	Describe: (Context) -> PromptState,
	Paint: ((BasePart, Context) -> ())?,
}

return Types
