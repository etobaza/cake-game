-- One base building: a part in the world, a data node and an FSM over it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BuildingsConfig = require(_Configs.Buildings)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local LoggerUtil = require(_Libs.Logger)
local StateMachine = require(_Libs.StateMachine)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "Building" })

--[[ Tables ]]--
local Building = {}
Building.__index = Building

export type Behavior = {
	EnsureState: (building: any) -> any?,
	BuildConfig: (building: any) -> any,
	[string]: any,
}

export type Visual = {
	Update: (self: any, deltaTime: number, now: number) -> (),
	Play: ((self: any) -> ())?,
	Destroy: (self: any) -> (),
}

export type Building = typeof(setmetatable(
	{} :: {
		Player: Player,
		Id: string,
		Kind: string,
		Index: number,
		Definition: BuildingsConfig.Kind,
		Behavior: Behavior?,
		Part: BasePart,
		State: any?,
		FSM: any?,
		Visual: Visual?,
		FoodVisual: (Visual & { Frame: CFrame, SetFrame: (self: any, frame: CFrame) -> () })?,
		Janitor: any,
		GardenAccumulator: number?,
		RailPath: any?,
		RailFeedRemaining: number?,
	},
	Building
))

--[[ Handling ]]--
function Building.new(
	player: Player,
	buildingId: string,
	kindName: string,
	definition: BuildingsConfig.Kind,
	behavior: Behavior?,
	part: BasePart
): Building
	local self = setmetatable({}, Building) :: Building

	self.Player = player
	self.Id = buildingId
	self.Kind = kindName
	self.Index = BuildingsConfig.GetIndex(buildingId)
	self.Definition = definition
	self.Behavior = behavior
	self.Part = part
	self.Visual = nil
	self.FoodVisual = nil
	self.Janitor = Janitor.new()

	if behavior then
		self:BuildBehavior(behavior)
	end

	return self
end

function Building:BuildBehavior(behavior: Behavior): ()
	local state = behavior.EnsureState(self)
	if not state then
		Logger:Warn(`{self.Id}: no data node, behavior skipped`)
		return
	end

	self.State = state

	local config = behavior.BuildConfig(self)
	config.errorHandler = config.errorHandler or function(message: string)
		Logger:Warn(`{self.Id}: {message}`)
	end

	self.FSM = StateMachine.new(config)
end

function Building:Update(deltaTime: number, now: number, paused: boolean?): ()
	if self.State and self.Behavior and self.Behavior.Update then
		self.Behavior.Update(self, deltaTime, now)
	end
	if self.FSM and not paused then
		self.FSM.params.Now = now
		self.FSM:Update(deltaTime)
	end

	if self.Visual then
		self.Visual:Update(deltaTime, now)
	end
	if self.FoodVisual then
		self.FoodVisual:Update(deltaTime, now)
	end
end

function Building:SetVisual(visual: Visual): ()
	self.Visual = visual
	self.Janitor:Add(visual, "Destroy", "Visual")
end

function Building:SetState(stateName: string): ()
	if self.FSM then
		self.FSM:SetState(stateName)
	end
end

function Building:GetState(): string?
	return if self.FSM then self.FSM:GetCurrentState() else nil
end

function Building:Destroy(): ()
	local destroy = self.Behavior and self.Behavior.Destroy
	if destroy then
		destroy(self)
	end
	self.Janitor:Destroy()
end

return Building
