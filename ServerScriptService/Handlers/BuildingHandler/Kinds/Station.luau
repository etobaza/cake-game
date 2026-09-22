--!strict
-- Kitchen station: mixer, ovens, freezer, coffee.
-- Transitions Idle/Loaded -> Mixing/Cooking -> Ready -> Burnt are declared in the FSM.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local TutorialPolicy = require(ReplicatedStorage.Shared.TutorialPolicy)
local BaseHandler = require(_Handlers.BaseHandler)
local Bus = require(_Shared.Bus)
local DataHandler = require(_Handlers.DataHandler)
local DayCycleHandler = require(_Handlers.DayCycleHandler)
local GameTypes = require(_Shared.GameTypes)
local Ingredients = require(_Configs.Registries.Ingredients)
local InventoryHandler = require(_Handlers.InventoryHandler)
local LoggerUtil = require(_Libs.Logger)
local MixerInteraction = require(_Configs.MixerInteraction)
local OvenFuel = require(_Configs.OvenFuel)
local PantryHandler = require(_Handlers.PantryHandler)
local PickupOrigin = require(script.Parent.Parent.PickupOrigin)
local PlayerHandler = require(_Handlers.PlayerHandler)
local Recipes = require(_Configs.Registries.Recipes)
local StateMachine = require(_Libs.StateMachine)
local UpgradeHandler = require(_Handlers.UpgradeHandler)

--[[ Constants ]]--
local FUEL: GameTypes.ItemKind = "Fuel"
local MIXER_LOCK_PREFIX = "Mixer:"

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "Station" })
local FuelRandom = Random.new()

--[[ Tables ]]--
local Station = {}

--[[ Private Functions ]]--
local function GetStations(building: any): any?
	local data = DataHandler:GetData(building.Player)

	return data and data.Session[building.Definition.StateField]
end

local function IsBurnable(building: any, recipe: Recipes.RecipeEntry): boolean
	return building.Definition.Burns == true and recipe.burnSeconds > 0
end

local function Reject(building: any, reason: string): boolean
	Bus.Progress.ActionFailed:FireClient(building.Player, reason)

	return false
end

-- Timers stop at the exact instant the fire went out, including a delayed server update.
local function HeatTime(state: any, now: number): number
	return if (state.HeatPausedAt or 0) > 0 then math.min(now, state.HeatPausedAt) else now
end

local function SetMixerLocked(building: any, isLocked: boolean): ()
	if building.Definition.Mixes then
		PlayerHandler:SetMovementLocked(building.Player, `{MIXER_LOCK_PREFIX}{building.Id}`, isLocked)
	end
end

-- The floor anchor faces out toward the aisle; the bowl mesh's imported axes do not.
-- Keep the root at standing height even when E was pressed while jumping or from the side.
local function AlignMixer(building: any): boolean
	local character = building.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
		or not humanoid
		or not root
		or not root:IsA("BasePart")
		or humanoid.Health <= 0
		or humanoid.Sit
	then
		return Reject(building, "too_far")
	end

	local anchor = BaseHandler:GetAnchor(building.Id)
	local transform = BaseHandler:GetTransform(building.Player)
	if not anchor or not transform then
		Logger:Warn(`Missing mixer placement for {building.Id}`)
		return Reject(building, "station_missing")
	end
	local floor = transform * anchor
	local outward = floor.LookVector * Vector3.new(1, 0, 1)
	if outward.Magnitude < 0.001 then
		Logger:Warn(`Mixer anchor must face the aisle: {building.Id}`)
		return Reject(building, "station_missing")
	end
	local bowl = building.Part.Position
	local position = bowl + outward.Unit * MixerInteraction.StandDistance
	local height = humanoid.HipHeight + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		if leg and leg:IsA("BasePart") then
			height += leg.Size.Y
		end
	end
	position = Vector3.new(position.X, floor.Position.Y + height, position.Z)
	local target = CFrame.lookAt(position, Vector3.new(bowl.X, position.Y, bowl.Z))
	-- PivotTo moves the model pivot; preserve its offset from HumanoidRootPart.
	character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

-- Loading and mixing reject the same wrong or surplus ingredient before changing the batch.
local function ingredientFailure(recipe: Recipes.RecipeEntry, state: any, ingredientId: string): string?
	local needed = recipe.ingredients[ingredientId]
	if not needed then
		return "ingredient_not_needed"
	end

	local loaded = (state.Loaded and state.Loaded[ingredientId]) or 0
	if loaded >= needed then
		return "ingredient_complete"
	end
	return nil
end

-- The mixer collects ingredients one by one instead of taking a ready dough.
local function LoadIngredient(building: any, held: any): boolean
	if not held or held.Kind ~= "Ingredient" then
		return Reject(building, "nothing_to_load")
	end

	local state = building.State
	local data = DataHandler:GetData(building.Player)
	local selectedId = data and data.Session.Cooking.SelectedRecipeId
	local recipe = selectedId and Recipes:Get(selectedId)
	if not recipe then
		return Reject(building, "select_recipe")
	end

	local failure = ingredientFailure(recipe, state, held.Id)
	if failure then
		return Reject(building, failure)
	end

	state.Loaded = state.Loaded or {}

	InventoryHandler:Pop(building.Player)
	state.Loaded[held.Id] = (state.Loaded[held.Id] or 0) + 1

	return true
end

-- Every state writes its own name into the data: that field is what the client reads.
local function BuildStates(building: any, state: any): any
	local function EnterIdle(): ()
		SetMixerLocked(building, false)
		state.State = "Idle"
		state.RecipeId = nil
		state.PhaseStartedAt = 0
		state.ReadyAt = 0
		state.BurnAt = 0
		state.HeatPausedAt = 0
		state.Loaded = {}
	end

	local function EnterBaking(stateName: string): () -> ()
		return function()
			SetMixerLocked(building, stateName == "Mixing")
			state.State = stateName
			state.PhaseStartedAt = workspace:GetServerTimeNow()
			state.BurnAt = 0
			state.HeatPausedAt = 0
		end
	end

	local function EnterLoaded(): ()
		SetMixerLocked(building, false)
		state.State = "Loaded"
		state.PhaseStartedAt = 0
		state.ReadyAt = 0
		state.BurnAt = 0
		state.HeatPausedAt = 0
	end

	local function EnterReady(): ()
		SetMixerLocked(building, false)
		state.State = "Ready"
		state.PhaseStartedAt = state.ReadyAt
		state.BurnAt = 0
		if building.Definition.Mixes then
			-- The completed batch keeps RecipeId; the next batch needs a fresh selection.
			local data = DataHandler:GetData(building.Player)
			if data then
				data.Session.Cooking.SelectedRecipeId = nil
			end
			state.Loaded = {}
		end

		local recipe = Recipes:Get(state.RecipeId)
		if not recipe or not IsBurnable(building, recipe) then
			return
		end

		local burnMult = UpgradeHandler:GetStat(building.Player, "BurnTimeMult")
		local data = DataHandler:GetData(building.Player)
		local seconds = recipe.burnSeconds * burnMult
		if data then
			seconds = TutorialPolicy.BurnSeconds(data.Cloud, seconds)
		end
		state.BurnAt = state.PhaseStartedAt + seconds
	end

	local function EnterBurnt(): ()
		SetMixerLocked(building, false)
		state.State = "Burnt"
		Logger:Debug(`{building.Player.Name}: {state.RecipeId} burned`)
	end

	return {
		Idle = { onEnter = EnterIdle },
		Loaded = { onEnter = EnterLoaded },
		Mixing = { onEnter = EnterBaking("Mixing") },
		Cooking = { onEnter = EnterBaking("Cooking") },
		Ready = { onEnter = EnterReady },
		Burnt = { onEnter = EnterBurnt },
	}
end

-- The only transitions the player does not push: the timers.
local function BuildTransitions(state: any): { StateMachine.Transition }
	local function IsBaked(params: any): boolean
		return HeatTime(state, params.Now) >= state.ReadyAt
	end

	local function IsOverdue(params: any): boolean
		return state.BurnAt > 0 and HeatTime(state, params.Now) >= state.BurnAt
	end

	return {
		{ from = { "Mixing", "Cooking" }, to = "Ready", condition = IsBaked },
		{ from = "Ready", to = "Burnt", condition = IsOverdue },
	}
end

--[[ Handling ]]--
function Station.EnsureState(building: any): any?
	local stations = GetStations(building)
	if not stations then
		return nil
	end

	if not stations[building.Id] then
		stations[building.Id] = {
			Kind = building.Kind,
			State = "Idle",
			RecipeId = nil,
			PhaseStartedAt = 0,
			ReadyAt = 0,
			BurnAt = 0,
			Fuel = 0,
			FuelEndsAt = 0,
			HeatPausedAt = 0,
			Loaded = {},
		}
	end

	return stations[building.Id]
end

function Station.BuildConfig(building: any): any
	local state = building.State
	local states = BuildStates(building, state)
	-- Rebinding a purchased/rebuilt station must not restart its current recipe or erase a pause.
	if building.Definition.UsesFuel then
		for _, entry in states do
			local enter = entry.onEnter
			entry.onEnter = function(previous: any): ()
				if previous then
					enter()
				end
			end
		end
	end

	return {
		-- The building may have been rebuilt mid-bake: the state comes from the data.
		initialState = state.State or "Idle",
		params = { Now = 0 },
		states = states,
		transitions = BuildTransitions(state),
	}
end

-- One press starts the selected recipe. A mixer holds the player's movement until its timed batch
-- reaches Ready; ovens and other autonomous stations do not lock the player.
function Station.Mix(building: any): boolean
	local state = building.State
	local data = DataHandler:GetData(building.Player)
	local recipeId = data and data.Session.Cooking.SelectedRecipeId
	local recipe = recipeId and Recipes:Get(recipeId)
	if data and not building.Definition.Mixes then
		recipe = Recipes:GetDirectRecipe(data.Session.Day.Menu, building.Kind, recipeId)
		recipeId = recipe and recipe.id
	end
	if not recipe then
		return Reject(building, "select_recipe")
	end

	if state.State ~= "Idle" then
		return Reject(building, "station_busy")
	end

	if building.Kind ~= Recipes:GetStartStation(recipe) then
		return Reject(building, "wrong_station")
	end

	if not DayCycleHandler:IsOnMenu(building.Player, recipe.id) then
		return Reject(building, "not_on_menu")
	end

	if building.Definition.Mixes then
		-- A stale Mix prompt must not bypass the ingredient refusal shown by the current prompt.
		local held = InventoryHandler:Peek(building.Player)
		local failure = if held and held.Kind == "Ingredient" then ingredientFailure(recipe, state, held.Id) else nil
		if failure then
			return Reject(building, failure)
		end

		-- Counting through the proxy only: `next` on a data table always reads empty, the values
		-- live behind its metatable.
		local loaded = state.Loaded or {}
		for ingredientId, amount in recipe.ingredients do
			if (loaded[ingredientId] or 0) < amount then
				return Reject(building, "missing_ingredients")
			end
		end

		if not AlignMixer(building) then
			return false
		end
		local duration = recipe.mixSeconds / UpgradeHandler:GetStat(building.Player, "MixSpeedMult")
		state.RecipeId = recipeId
		state.ReadyAt = workspace:GetServerTimeNow() + duration
		building:SetState("Mixing")

		return true
	end

	state.RecipeId = recipeId
	Station.Update(building, 0, workspace:GetServerTimeNow())
	if building.Definition.UsesFuel and state.Fuel == 0 then
		building:SetState("Loaded")
		return true
	end

	state.ReadyAt = workspace:GetServerTimeNow() + recipe.cookSeconds
	building:SetState("Cooking")

	return true
end

-- RailCart owns removing the matching delivery immediately after this non-yielding acceptance.
function Station.LoadRailIngredient(building: any, ingredientId: string): boolean
	if not building.Definition.Mixes or not building.State or building.State.State ~= "Idle" then
		return false
	end
	local data = DataHandler:GetData(building.Player)
	if not data or data.Session.Day.Phase == "Summary" then
		return false
	end
	local recipeId = data.Session.Cooking.SelectedRecipeId
	local recipe = recipeId and Recipes:Get(recipeId)
	if
		not recipe
		or building.Kind ~= Recipes:GetStartStation(recipe)
		or not DayCycleHandler:IsOnMenu(building.Player, recipe.id)
	then
		return false
	end
	if ingredientFailure(recipe, building.State, ingredientId) then
		return false
	end
	local state = building.State
	state.Loaded = state.Loaded or {}
	state.Loaded[ingredientId] = (state.Loaded[ingredientId] or 0) + 1
	return true
end

-- Moving from hands: an ingredient into the mixer, dough into an oven, freezer or coffee machine.
function Station.Load(building: any): boolean
	local state = building.State
	if state.State ~= "Idle" then
		return Reject(building, "station_busy")
	end

	local held = InventoryHandler:Peek(building.Player)

	if building.Definition.Mixes then
		return LoadIngredient(building, held)
	end

	local feedback = building.Definition.LoadFeedback
	if not held or held.Kind ~= "Dough" then
		return Reject(building, if feedback then feedback.Missing else "nothing_to_load")
	end

	local recipe = Recipes:Get(held.Id)
	if not recipe or recipe.station ~= building.Kind then
		return Reject(building, if feedback then feedback.WrongRecipe else "wrong_station")
	end

	InventoryHandler:Pop(building.Player)
	state.RecipeId = recipe.id

	-- The dough stays inside an unfuelled oven. Adding a log later starts this same recipe.
	Station.Update(building, 0, workspace:GetServerTimeNow())
	if building.Definition.UsesFuel and state.Fuel == 0 then
		building:SetState("Loaded")
		return true
	end

	state.ReadyAt = workspace:GetServerTimeNow() + recipe.cookSeconds

	building:SetState("Cooking")

	return true
end

-- The whole batch is abandoned at once, from the recipe list at the mixer. Garden produce goes back
-- into the pantry; staples were free to begin with. The selection is dropped with it, so the list
-- offers Start again and the mixer is free for another dish.
function Station.Cancel(building: any): boolean
	if not building.Definition.Mixes then
		return Reject(building, "wrong_station")
	end

	if building.State.State ~= "Idle" then
		return Reject(building, "station_busy")
	end

	local data = DataHandler:GetData(building.Player)
	if not data then
		return false
	end

	local hadSomething = data.Session.Cooking.SelectedRecipeId ~= nil
	for ingredientId, amount in building.State.Loaded or {} do
		if amount <= 0 then
			continue
		end

		hadSomething = true
		if not Ingredients:IsInfinite(ingredientId) then
			PantryHandler:Add(building.Player, ingredientId, amount)
		end
	end

	if not hadSomething then
		return Reject(building, "nothing_to_cancel")
	end

	building.State.Loaded = {}
	data.Session.Cooking.SelectedRecipeId = nil

	return true
end

-- Garden produce lives in Pantry because it survives harvests and day changes. The authored kitchen
-- has no shelf models for those items, so the selected-recipe button withdraws them at the mixer.
function Station.TakePantry(building: any, ingredientId: string): boolean
	if not building.Definition.Mixes then
		return Reject(building, "wrong_station")
	end

	if building.State.State ~= "Idle" then
		return Reject(building, "station_busy")
	end

	local ingredient = Ingredients:Get(ingredientId)
	local data = DataHandler:GetData(building.Player)
	local recipeId = data and data.Session.Cooking.SelectedRecipeId
	local recipe = recipeId and Recipes:Get(recipeId)
	local needed = recipe and recipe.ingredients[ingredientId]
	if not recipeId or not ingredient or Ingredients:IsInfinite(ingredientId) or not needed then
		return Reject(building, "ingredient_not_needed")
	end

	if not DayCycleHandler:IsOnMenu(building.Player, recipeId) then
		return Reject(building, "not_on_menu")
	end

	local loaded = (building.State.Loaded and building.State.Loaded[ingredientId]) or 0
	local carried = InventoryHandler:CountMatching(building.Player, "Ingredient", ingredientId)
	if loaded + carried >= needed then
		return Reject(building, "ingredient_complete")
	end

	return PantryHandler:Take(building.Player, ingredientId, nil, PickupOrigin.ForBuilding(building))
end

-- Take from the station. Burnt goes into the hands and has to be carried to the trash.
function Station.Collect(building: any): boolean
	local state = building.State

	if state.State == "Burnt" then
		local item: GameTypes.ItemStack = { Kind = "Burnt", Id = state.RecipeId or "" }
		if not InventoryHandler:Push(building.Player, item, PickupOrigin.ForBuilding(building)) then
			return Reject(building, "hands_full")
		end

		building:SetState("Idle")

		return true
	end

	if state.State ~= "Ready" then
		return Reject(building, "not_ready")
	end

	local recipe = Recipes:Get(state.RecipeId)
	if not recipe then
		building:SetState("Idle")
		return false
	end

	-- Dough leaves the mixer when the recipe continues on another station.
	local isFinished = not building.Definition.Mixes or recipe.cookSeconds == 0
	local item: GameTypes.ItemStack = { Kind = if isFinished then "Dish" else "Dough", Id = recipe.id }

	if not InventoryHandler:Push(building.Player, item, PickupOrigin.ForBuilding(building)) then
		return Reject(building, "hands_full")
	end

	building:SetState("Idle")

	return true
end

-- A carried log refreshes the fire, even while baking or while a finished dish waits inside.
-- Remaining heat is replaced, never stacked. The upgrade extends the next log's lifetime.
function Station.Refuel(building: any): boolean
	if not building.Definition.UsesFuel then
		return false
	end
	if not InventoryHandler:FindIndex(building.Player, FUEL) then
		return Reject(building, "need_firewood")
	end

	local state = building.State
	local recipe = if state.State == "Loaded" then Recipes:Get(state.RecipeId) else nil
	if state.State == "Loaded" and not recipe then
		return Reject(building, "wrong_station")
	end
	local now = workspace:GetServerTimeNow()
	Station.Update(building, 0, now)
	if not InventoryHandler:TakeMatching(building.Player, FUEL) then
		return false
	end
	local seconds = UpgradeHandler:GetStat(building.Player, "FuelBurnSeconds")
	state.Fuel = 1
	state.FuelEndsAt = now + seconds + FuelRandom:NextNumber(-OvenFuel.DurationVariation, OvenFuel.DurationVariation)
	if (state.HeatPausedAt or 0) > 0 then
		local paused = now - state.HeatPausedAt
		for _, field in { "PhaseStartedAt", "ReadyAt", "BurnAt" } do
			if state[field] > 0 then
				state[field] = state[field] + paused
			end
		end
		state.HeatPausedAt = 0
	end
	if recipe then
		state.ReadyAt = now + recipe.cookSeconds
		building:SetState("Cooking")
	end

	return true
end

function Station.Update(building: any, _deltaTime: number, now: number): ()
	if not building.Definition.UsesFuel then
		return
	end
	local state = building.State
	local endsAt = state.FuelEndsAt or 0
	if state.Fuel == 0 or endsAt <= 0 or now < endsAt then
		return
	end
	state.Fuel = 0
	state.FuelEndsAt = 0
	if state.State == "Cooking" or state.State == "Ready" then
		state.HeatPausedAt = endsAt
	end
end

-- A new day clears a station left burnt overnight: the mess is thrown out with the morning trash,
-- so yesterday's mistake cannot keep an oven locked through the whole next day.
function Station.StartDay(building: any): ()
	if building:GetState() == "Burnt" then
		building:SetState("Idle")
	end
end

function Station.Destroy(building: any): ()
	SetMixerLocked(building, false)
end

-- Takes a finished dish past the player's hands: used by the assistant.
function Station.TakeReady(building: any): string?
	local state = building.State
	if state.State ~= "Ready" then
		return nil
	end

	local recipe = Recipes:Get(state.RecipeId)
	if not recipe or (building.Definition.Mixes and recipe.cookSeconds > 0) then
		return nil
	end

	building:SetState("Idle")

	return recipe.id
end

return Station
