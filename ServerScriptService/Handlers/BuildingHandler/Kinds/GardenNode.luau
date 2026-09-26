--!strict
-- Repeating sources. One shared building tick advances active time, never offline time.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Handlers = ServerScriptService.Handlers
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local AnimalCare = require(_Shared.AnimalCare)
local BrushingInteraction = require(script.Parent.Parent.BrushingInteraction)
local Config = require(_Shared.Configs.Garden)
local Care = require(script.Parent.Parent.GardenCare)
local Data = require(_Handlers.DataHandler)
local Inventory = require(_Handlers.InventoryHandler)
local Pantry = require(_Handlers.PantryHandler)
local Economy = require(_Handlers.EconomyHandler)
local PickupOrigin = require(script.Parent.Parent.PickupOrigin)
local Upgrades = require(_Handlers.UpgradeHandler)
local VFX = require(_Shared.Configs.VFX)
local WateringInteraction = require(script.Parent.Parent.WateringInteraction)

--[[ Tables ]]--
local GardenNode = {}

--[[ Private Functions ]]--
local function active(building: any): boolean
	local data = Data:GetData(building.Player)
	return data ~= nil and data.Session.Day.Phase ~= "Summary"
end

local function cancelCare(building: any): ()
	WateringInteraction.End(building)
	BrushingInteraction.End(building)
	if building.State.CareUntil ~= 0 then
		building.State.CareUntil = 0
	end
	building.Part:SetAttribute("GardenCareUntil", nil)
	building.Part:SetAttribute("GardenCareAction", nil)
end

local function canContinue(building: any, strategy: any): boolean
	local character = building.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return active(building)
		and root ~= nil
		and root:IsA("BasePart")
		and humanoid ~= nil
		and humanoid.Health > 0
		and not humanoid.Sit
		and (root.Position - building.Part.Position).Magnitude <= Config.InteractionRange
		and strategy.CanCare(Inventory:Peek(building.Player))
		and (
			building.State.CareUntil <= 0
			or Config.Sources[building.Id].Care ~= "Animal"
			or BrushingInteraction.CanContinue(building)
		)
end

local function advanceGrowth(building: any, strategy: any, day: number, deltaTime: number): ()
	local state = building.State
	if state.CareUntil > 0 and Config.Sources[building.Id].Care == "Animal" then
		building.GardenAccumulator = 0
		return
	end
	building.GardenAccumulator += deltaTime
	if building.GardenAccumulator < 1 then
		return
	end
	local seconds = building.GardenAccumulator
	building.GardenAccumulator = 0
	local supplied = strategy.Step(state, seconds, day, Upgrades, building.Player)
	local source = Config.Sources[building.Id]
	-- Lemon Cake removes an uncollected animal product when DirtMaterial finishes.
	if source.Care == "Animal" and state.CareRemaining <= 0 and state.CleanDay ~= day then
		state.Stock = 0
		state.GrowRemaining = source.ProduceSeconds or Config.ProduceSeconds
		return
	end
	local held = Inventory:Peek(building.Player)
	if source.Capacity == 1 and held and held.SourceId == building.Id then
		return
	end
	if state.Stock >= (source.Capacity or Config.Capacity) or supplied <= 0 then
		return
	end
	local remaining = state.GrowRemaining - supplied * strategy.Speed(Upgrades, building.Player)
	if remaining <= 0 then
		state.Stock += 1
		remaining = source.ProduceSeconds or Config.ProduceSeconds
	end
	state.GrowRemaining = remaining
end

--[[ Handling ]]--
function GardenNode.EnsureState(building: any): any?
	local data = Data:GetData(building.Player)
	local source = Config.Sources[building.Id]
	if not data or not source then
		return nil
	end
	local group = data.Cloud.Garden[source.Group]
	if not group[building.Id] then
		group[building.Id] = {
			Stock = 0,
			GrowRemaining = source.ProduceSeconds or Config.ProduceSeconds,
			CareRemaining = 0,
			CleanDay = 0,
			Day = data.Cloud.Day,
			CareUntil = 0,
			State = "Paused",
		}
	end
	local state = group[building.Id]
	local capacity = source.Capacity or Config.Capacity
	if state.Stock > capacity then
		-- Preserve existing saves when switching animal baskets from four portions to one.
		Pantry:Add(building.Player, source.Produce, state.Stock - capacity)
		state.Stock = capacity
	end
	state.GrowRemaining = math.min(state.GrowRemaining, source.ProduceSeconds or Config.ProduceSeconds)
	group[building.Id].CareUntil = 0
	building.GardenAccumulator = 0
	return group[building.Id]
end

function GardenNode.BuildConfig(building: any): any
	local states = {}
	for _, name in { "Dry", "Growing", "Full", "Caring", "Paused" } do
		states[name] = {
			onEnter = function(): ()
				building.State.State = name
			end,
		}
	end
	return { initialState = "Paused", params = { Now = 0 }, states = states, transitions = {} }
end

function GardenNode.StartDay(building: any): ()
	local data = Data:GetData(building.Player)
	if not data then
		return
	end
	local state = building.State
	if state.Day == data.Cloud.Day then
		return
	end
	if Config.Sources[building.Id].Care == "Animal" and state.Day ~= data.Cloud.Day then
		state.CareRemaining = 0
		state.CleanDay = 0
	end
	state.Day = data.Cloud.Day
end

function GardenNode.Update(building: any, deltaTime: number, now: number): ()
	local state = building.State
	local source = Config.Sources[building.Id]
	local strategy = Care[source.Care]
	local data = Data:GetData(building.Player)
	if not data then
		cancelCare(building)
		return
	end
	GardenNode.StartDay(building)
	if state.CareUntil > 0 then
		if not canContinue(building, strategy) then
			cancelCare(building)
		elseif now >= state.CareUntil then
			local clean = if source.Care == "Animal" then AnimalCare.Cleanliness(state, data.Cloud.Day) else 1
			strategy.Complete(state, data.Cloud.Day, Upgrades, building.Player)
			cancelCare(building)
			if clean <= Config.BrushExperienceThreshold then
				Economy:AwardXP(building.Player, (1 - clean) * Config.BrushExperience)
			end
		end
	end
	if not active(building) then
		building.GardenAccumulator = 0
		if building:GetState() ~= "Paused" then
			building:SetState("Paused")
		end
		return
	end
	advanceGrowth(building, strategy, data.Cloud.Day, deltaTime)
	local nextState = if state.CareUntil > 0
		then "Caring"
		elseif state.Stock >= (source.Capacity or Config.Capacity) then "Full"
		elseif source.Care == "Hive" or state.CareRemaining > 0 or state.CleanDay == data.Cloud.Day then "Growing"
		else "Dry"
	if building:GetState() ~= nextState then
		building:SetState(nextState)
	end
end

function GardenNode.Tend(building: any): boolean
	local source = Config.Sources[building.Id]
	if source.Care == "Hive" or not active(building) or building.State.CareUntil > 0 then
		return false
	end
	if not canContinue(building, Care[source.Care]) then
		Bus.Progress.ActionFailed:FireClient(
			building.Player,
			if source.Care == "Plant" then "need_watering_can" else "hands_full"
		)
		return false
	end
	if source.Care == "Plant" and not WateringInteraction.Begin(building) then
		return false
	end
	if source.Care == "Animal" and not BrushingInteraction.Begin(building) then
		return false
	end
	local duration = if source.BrushAnimation then source.BrushAnimation.Duration else Config.CareSeconds
	building.State.CareUntil = workspace:GetServerTimeNow() + duration
	building.Part:SetAttribute("GardenCareUntil", building.State.CareUntil)
	building.Part:SetAttribute("GardenCareAction", if source.Care == "Plant" then "Water" else "Brush")
	local character = building.Player.Character
	if source.Care == "Plant" and character then
		character:SetAttribute(VFX.WaterUntilAttribute, building.State.CareUntil)
	end
	building:SetState("Caring")
	return true
end

function GardenNode.Harvest(building: any): boolean
	if not active(building) or building.State.CareUntil > 0 then
		return false
	end
	local source = Config.Sources[building.Id]
	local held = Inventory:Peek(building.Player)
	if
		source.Capacity == 1
		and held
		and held.Kind == "Ingredient"
		and held.Id == source.Produce
		and held.SourceId == building.Id
		and building.State.Stock == 0
	then
		Inventory:Pop(building.Player)
		building.State.Stock = 1
		return true
	end
	if building.State.Stock <= 0 then
		Bus.Progress.ActionFailed:FireClient(building.Player, "nothing_to_harvest")
		return false
	end
	local output = building.Part:FindFirstChild("AnimalProduce")
	local origin = if output and output:IsA("BasePart") then output.Position else PickupOrigin.ForBuilding(building)
	if
		not Inventory:Push(
			building.Player,
			{ Kind = "Ingredient", Id = source.Produce, SourceId = if source.Capacity == 1 then building.Id else nil },
			origin
		)
	then
		Bus.Progress.ActionFailed:FireClient(building.Player, "hands_full")
		return false
	end
	building.State.Stock -= 1
	return true
end

function GardenNode.Destroy(building: any): ()
	if building.State then
		cancelCare(building)
	end
end
return GardenNode
