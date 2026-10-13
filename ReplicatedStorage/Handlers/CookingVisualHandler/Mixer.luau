--!strict
-- Mixer surface visual: a continuous swirl of local ingredient clones that converges over the bowl,
-- blends toward the batter color, and resolves into a growing local dough. It hides the server
-- ingredient pieces while active and restores them when the batch ends, so the authoritative server
-- deletion at Ready and the FreshFood squash on the result take over cleanly.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--[[ References ]]
--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]
--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local CookingMotion = require(_Configs.CookingMotion)
local MixerIngredients = require(_Configs.MixerIngredients)
local FoodModel = require(_Shared.FoodModel)
local Recipes = require(_Configs.Registries.Recipes)
local Util = require(_Shared.CookingMotionUtil)

--[[ Types ]]
--
type DoughPart = { Part: BasePart, Offset: CFrame, Size: Vector3 }
type Clone = { Parts: { DoughPart }, BaseColor: Color3, Angle: number }
type MaskedPart = { Part: BasePart, Masked: number, Original: number }

export type MixerVisual = Util.VisualEntry

--[[ Constants ]]
--
local TAU = math.pi * 2
local TUNING = CookingMotion.Mixer
local SURFACE = CookingMotion.Surface
local INGREDIENT = CookingMotion.Ingredient
local STATE = CookingMotion.State

--[[ Private helpers ]]
--
local function colorFor(ingredientId: string?, fallback: Color3): Color3
	local entry = ingredientId ~= nil and MixerIngredients.Entries[ingredientId] or nil
	return if entry then entry.Color else fallback
end

-- A disposable, texture-stripped copy of a server ingredient, tinted to its batter color. The
-- original pieces are only hidden locally, never mutated, exactly as the carried ingredient copies
-- are prepared elsewhere.
local function buildClone(source: Instance, color: Color3, parent: Instance, home: CFrame): { DoughPart }
	local copy = source:Clone()
	local parts: { DoughPart } = {}
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("SurfaceAppearance") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.Color = color
			parts[#parts + 1] =
				{ Part = descendant, Offset = home:ToObjectSpace(descendant.CFrame), Size = descendant.Size }
		end
	end
	if copy:IsA("BasePart") then
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Massless = true
		copy.CastShadow = false
		copy.Material = Enum.Material.SmoothPlastic
		copy.Color = color
		parts[#parts + 1] = { Part = copy, Offset = home:ToObjectSpace(copy.CFrame), Size = copy.Size }
	end
	copy.Parent = parent
	return parts
end

--[[ Factory ]]
--
local function new(surface: Folder): MixerVisual
	local janitor = Janitor.new()
	local active = false

	local doughParts: { DoughPart } = {}
	local clones: { Clone } = {}
	local masked: { MaskedPart } = {}
	local sources: { Instance } = {}
	local batterColor = TUNING.DefaultBatterColor

	local function restoreMasks(): ()
		for _, record in masked do
			local part = record.Part
			-- Restore only our own masking value; a newer owner that overwrote it keeps its value.
			if part.Parent ~= nil and part.LocalTransparencyModifier == record.Masked then
				part.LocalTransparencyModifier = record.Original
			end
		end
		table.clear(masked)
	end

	local function deactivate(): ()
		if not active then
			return
		end
		active = false
		restoreMasks()
		janitor:Remove("Dough")
		janitor:Remove("Container")
		table.clear(doughParts)
		table.clear(clones)
		table.clear(sources)
	end

	local function collectIngredients(): { Instance }
		local found: { Instance } = {}
		for _, child in surface:GetChildren() do
			if child:GetAttribute(INGREDIENT.IngredientId) ~= nil then
				found[#found + 1] = child
			end
		end
		table.sort(found, function(a: Instance, b: Instance): boolean
			local ai = Util.GetNumber(a, INGREDIENT.PortionIndex) or 0
			local bi = Util.GetNumber(b, INGREDIENT.PortionIndex) or 0
			return ai < bi
		end)
		return found
	end

	local function activate(surfaceFrame: CFrame, recipeId: string): boolean
		local ingredients = collectIngredients()
		local recipe = Recipes:Get(recipeId)
		local expected = 0
		if not recipe then
			return false
		end
		for _, amount in recipe.ingredients do
			expected += amount
		end
		-- A tag can arrive before the portions. Wait for the complete accepted batch before masking.
		if #ingredients < expected then
			return false
		end
		for _, source in ingredients do
			local part = source:FindFirstChildWhichIsA("BasePart", true)
			if not part or part.Transparency >= 1 or part.LocalTransparencyModifier >= 1 then
				return false
			end
		end
		local holder = Instance.new("Folder")
		holder.Name = "MixerVisual"
		holder.Parent = Workspace
		janitor:Add(holder, "Destroy", "Container")

		sources = ingredients
		local slotStep = TAU / TUNING.SlotCount
		for index = 1, math.min(#ingredients, TUNING.SlotCount) do
			local source = ingredients[index]
			local ingredientId = Util.GetString(source, INGREDIENT.IngredientId)
			local portion = Util.GetNumber(source, INGREDIENT.PortionIndex) or index
			local color = colorFor(ingredientId, batterColor)

			local angle = (portion - 1) * slotStep
			local home = surfaceFrame
				* CFrame.new(
					math.cos(angle) * TUNING.SlotRadius,
					TUNING.SlotHeight,
					math.sin(angle) * TUNING.SlotRadius
				)
			local parts = buildClone(source, color, holder, home)
			clones[#clones + 1] = { Parts = parts, BaseColor = color, Angle = angle }

			-- Hide the authoritative server pieces while the local swirl stands in for them.
			for _, descendant in source:GetDescendants() do
				if descendant:IsA("BasePart") then
					masked[#masked + 1] =
						{ Part = descendant, Masked = 1, Original = descendant.LocalTransparencyModifier }
					descendant.LocalTransparencyModifier = 1
				end
			end
			if source:IsA("BasePart") then
				masked[#masked + 1] = { Part = source, Masked = 1, Original = source.LocalTransparencyModifier }
				source.LocalTransparencyModifier = 1
			end
		end

		local built = FoodModel.ForItem(recipeId, "Dough", holder, TUNING.DoughMaxSize)
		if not built then
			-- Missing asset: drop the holder and retry next frame rather than leave a bare bowl.
			janitor:Remove("Container")
			table.clear(clones)
			restoreMasks()
			return false
		end
		janitor:Add(built, "Destroy", "Dough")
		for _, entry in built.Parts do
			doughParts[#doughParts + 1] = { Part = entry.Part, Offset = entry.Offset, Size = entry.Part.Size }
		end

		active = true
		return true
	end

	local function update(surfaceFrame: CFrame, progress: number): ()
		local converge = Util.SmoothRange(progress, TUNING.ConvergeStart, 1)
		local radius = TUNING.SlotRadius * (1 - converge * (1 - TUNING.ConvergeRadiusFraction))
		local swirl = progress * TAU * TUNING.SwirlRevolutions
		local fade = Util.SmoothRange(progress, TUNING.BlendFadeStart, 1)

		for _, clone in clones do
			local angle = clone.Angle + swirl
			local bob = math.sin(swirl + clone.Angle) * TUNING.BobHeight * (1 - converge)
			local offset = CFrame.new(math.cos(angle) * radius, TUNING.SlotHeight + bob, math.sin(angle) * radius)
			local pivot = surfaceFrame * offset * CFrame.Angles(0, -angle, 0)
			local blended = clone.BaseColor:Lerp(batterColor, converge)
			local portionScale = 1 - converge * (1 - TUNING.ConvergedScale)
			for _, record in clone.Parts do
				local part = record.Part
				part.Size = record.Size * portionScale
				part.CFrame = Util.ScaleAboutFrame(pivot, record.Offset, Vector3.one * portionScale)
				part.Color = blended
				part.Transparency = fade
			end
		end

		-- The dough grows from a seed to full size as the batter blends, ending at the dough
		-- location so the server result and its FreshFood squash can take over seamlessly.
		local growth = TUNING.DoughMinScale + (1 - TUNING.DoughMinScale) * Util.Smoothstep(progress)
		local scale = Vector3.new(growth, growth, growth)
		for _, record in doughParts do
			record.Part.Size = record.Size * growth
			record.Part.CFrame = Util.ScaleAboutFrame(surfaceFrame, record.Offset, scale)
		end
	end

	local function focus(): Vector3?
		local frame = Util.GetCFrame(surface, SURFACE.SurfaceFrame)
		if frame then
			return frame.Position
		end
		for _, child in surface:GetChildren() do
			if child:IsA("Model") then
				return child:GetPivot().Position
			elseif child:IsA("BasePart") then
				return child.Position
			end
		end
		return nil
	end

	local function step(context: Util.StepContext): ()
		-- Only the mixer station swirls; other cooking surfaces present nothing from this module.
		if Util.GetString(surface, SURFACE.StationKind) ~= "Mixer" then
			deactivate()
			return
		end

		local state = Util.GetString(surface, SURFACE.StationState)
		if context.Presenting or context.Culled or state ~= STATE.Mixing then
			-- Presentation suppresses mixing (and releases the source mask); culling and any other
			-- state pause it too. Restoring here lets the mask hand back to a newer owner.
			deactivate()
			return
		end

		local surfaceFrame = Util.GetCFrame(surface, SURFACE.SurfaceFrame)
		local recipeId = Util.GetString(surface, SURFACE.RecipeId)
		if not surfaceFrame or not recipeId then
			return
		end

		batterColor = Util.GetColor3(surface, SURFACE.BatterColor) or TUNING.DefaultBatterColor
		local mixStarted = Util.GetNumber(surface, SURFACE.MixStartedAt)
		local mixReady = Util.GetNumber(surface, SURFACE.MixReadyAt)
		if not mixStarted or not mixReady or mixStarted <= 0 or mixReady <= mixStarted then
			return
		end
		if active then
			local ingredients = collectIngredients()
			local changed = #ingredients ~= #sources
			for index, source in sources do
				if ingredients[index] ~= source then
					changed = true
				end
			end
			for _, record in masked do
				if record.Part.Transparency >= 1 or record.Part.Parent == nil then
					changed = true
				end
			end
			if changed then
				deactivate()
			end
		end
		if not active and not activate(surfaceFrame, recipeId) then
			return
		end

		local pausedAt = Util.GetNumber(surface, SURFACE.PausedAt) or 0
		local heatPausedAt = Util.GetNumber(surface, SURFACE.HeatPausedAt) or 0
		local progress = Util.PhaseAlpha(mixStarted, mixReady, { pausedAt, heatPausedAt }, context.Now)

		update(surfaceFrame, progress)
	end

	local function destroy(): ()
		deactivate()
		janitor:Destroy()
	end

	return {
		Focus = focus,
		Step = step,
		Destroy = destroy,
	}
end

return {
	new = new,
}
