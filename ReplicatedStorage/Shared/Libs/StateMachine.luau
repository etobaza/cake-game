--[[
	StateMachine.luau
	Optimized Finite State Machine Implementation
	codebykoi <3
	Version 2.0.4

	A robust finite state machine implementation with support for:
	- State transitions with conditions and priorities
	- State entry/exit/update callbacks
	- State transition history with circular buffer
	- Transition caching for performance optimization
	- Custom error handling
	- Explicit transition permissions

	Dependencies:
	-------------
	• Signal

	Types:
	------
	State: Represents a single state in the state machine
		• name: string - Unique identifier for the state
		• onEnter: (fromState: State?, ...any) -> () - Called when entering state
		• onExit: (toState: State?, ...any) -> () - Called when exiting state  
		• onUpdate: (dt: number) -> () - Called each frame while state is active
		• allowedTransitions: {[string]: boolean}? - Whitelist/blacklist for transitions

	Transition: Defines a possible transition between states
		• from: string | {string} - Source state(s) or "*" for any state
		• to: string - Target state name
		• condition: (params: {any}) -> boolean - Function that must return true for transition
		• onTransition: (() -> ())? - Optional callback during transition
		• priority: number? - Higher priority transitions are evaluated first

	StateMachineConfig: Configuration object for creating a state machine
		• initialState: string - Starting state name
		• states: {[string]: StateDefinition} - Table of available states
		• transitions: {Transition}? - Optional list of transitions
		• params: {[any]: any}? - Optional shared parameters for states
		• historySize: number? - Maximum history entries (default: 10)
		• errorHandler: ((string) -> ())? - Custom error handler function

	Usage Example:
	--------------
	local fsm = StateMachine.new({
		initialState = "idle",
		states = {
		
			idle = {
				onEnter = function() print("Entering idle") end,
				onUpdate = function(dt) end,
				allowedTransitions = { walk = true, jump = true } -- Explicitly allowed
			},
				
			walk = {
				onEnter = function(from) print("Starting to walk from", from) end,
				onExit = function(to) print("Stopping walk to", to) end
			},
		},
			
		transitions = {
			{
				from = "idle", 
				to = "walk",
				condition = function(params) return params.isMoving end,
				priority = 1
			}
		},
		
		params = {
			value1 = 10,
			value2 = "hello",
		},
		
		})

		-- Update state machine each frame
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			fsm:Update(dt)
		end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Libs.Signal)

local StateMachine = {}
StateMachine.__index = StateMachine

export type State = {
	name: string,
	onEnter: (fromState: State?, ...any) -> (),
	onExit: (toState: State?, ...any) -> (),
	onUpdate: (dt: number) -> (),
	allowedTransitions: { [string]: boolean }?,
}

-- What a config passes in: the key becomes `name` and missing callbacks default to no-ops.
export type StateDefinition = {
	name: string?,
	onEnter: ((fromState: State?, ...any) -> ())?,
	onExit: ((toState: State?, ...any) -> ())?,
	onUpdate: ((dt: number) -> ())?,
	allowedTransitions: { [string]: boolean }?,
}

export type Transition = {
	from: string | { string },
	to: string,
	condition: (params: { any }) -> boolean,
	onTransition: (() -> ())?,
	priority: number?,
}

type StateMachineConfig = {
	initialState: string,
	states: { [string]: StateDefinition },
	transitions: { Transition }?,
	params: { [any]: any }?,
	historySize: number?,
	errorHandler: ((string) -> ())?,
}

--[[
	Creates a new StateMachine instance
	@param config: StateMachineConfig - Configuration object defining states, transitions, and behavior
	@return StateMachine - New state machine instance
	@throws Error if initial state is undefined or transitions reference undefined states
]]
function StateMachine.new(config: StateMachineConfig)
	local self = setmetatable({
		current = nil :: State?, -- Current active state
		states = {}, -- Registered states by name
		fromTransitions = {}, -- Transitions indexed by source state
		params = config.params or {}, -- Shared parameters for states/transitions
		history = {}, -- State history (circular buffer)
		onStateChange = Signal(), -- Signal fired on state changes
		historySize = config.historySize or 10, -- Maximum history entries
		errorHandler = config.errorHandler or error, -- Custom error handler
		_historyIndex = 0, -- Circular buffer current position
		_transitionCache = {}, -- Cached sorted transitions by state
	}, StateMachine)

	self:_validateConfig(config)
	self:_registerStates(config.states)
	self:_registerTransitions(config.transitions)
	self:SetState(config.initialState)

	return self
end

--[[ PUBLIC METHODS ]]

--[[
	Changes the current state to the specified state
	@param newState: string - Name of state to transition to
	@param ...: any - Additional arguments passed to onExit and onEnter callbacks
	
	Note: 
	- Checks if transition is allowed via allowedTransitions table
	- Calls onExit on current state (if any)
	- Calls onEnter on new state
	- Fires onStateChange signal
	- Adds previous state to history
]]
function StateMachine:SetState(newState: string, ...: any)
	local nextState = self.states[newState]
	if not nextState then
		self.errorHandler(`Attempted to switch to undefined state '${newState}'`)
		return
	end

	local currentState = self.current
	if currentState == nextState then
		return
	end

	-- Check if transition is explicitly allowed/disallowed
	if currentState and currentState.allowedTransitions then
		if currentState.allowedTransitions[nextState.name] == false then
			self.errorHandler(`Transition from '${currentState.name}' to '${nextState.name}' not allowed`)
			return
		end
	end

	-- Execute state transition
	if currentState then
		currentState.onExit(nextState, ...)
		self:_addToHistory(currentState)
	end

	self.current = nextState
	nextState.onEnter(currentState, ...)
	self.onStateChange:Fire(nextState, currentState)
end

--[[
	Updates the current state and evaluates transitions
	@param dt: number - Delta time since last update
	
	Note:
	- Calls onUpdate on current state
	- Evaluates transitions in priority order
	- Uses cached transitions for performance
	- Only executes the highest priority valid transition per update
]]
function StateMachine:Update(dt: number)
	if not self.current then
		return
	end

	self.current.onUpdate(dt)

	local currentStateName = self.current.name

	-- Cache transitions for current state to avoid repeated sorting
	if not self._transitionCache[currentStateName] then
		local transitions = {}

		-- Collect transitions for current state and wildcard transitions
		if self.fromTransitions[currentStateName] then
			for _, t in self.fromTransitions[currentStateName] do
				table.insert(transitions, t)
			end
		end
		if self.fromTransitions["*"] then
			for _, t in self.fromTransitions["*"] do
				table.insert(transitions, t)
			end
		end

		-- Sort by priority and cache
		table.sort(transitions, function(t1, t2)
			return (t1.priority or 0) > (t2.priority or 0)
		end)
		self._transitionCache[currentStateName] = transitions
	end

	-- Evaluate transitions in priority order
	for _, transition in self._transitionCache[currentStateName] do
		if transition.condition(self.params) then
			if transition.onTransition then
				transition.onTransition(self.params, currentStateName, transition.to)
			end

			self:SetState(transition.to)
			break -- Only process highest priority valid transition
		end
	end
end

--[[
	Gets the name of the current state
	@return string? - Current state name or nil if no state active
]]
function StateMachine:GetCurrentState(): string?
	return self.current and self.current.name
end

--[[
	Gets state transition history in chronological order (oldest first)
	@return {string} - Array of state names representing transition history
]]
function StateMachine:GetStateHistory(): { string }
	local count = #self.history
	if count == 0 then
		return {}
	end

	local result = {}
	if count < self.historySize then
		-- History not yet full - return all entries
		for i = 1, count do
			table.insert(result, self.history[i])
		end
	else
		-- History full - reconstruct chronological order from circular buffer
		local start = self._historyIndex + 1
		if start > self.historySize then
			start = 1
		end

		for _ = 1, self.historySize do
			table.insert(result, self.history[start])
			start = start + 1
			if start > self.historySize then
				start = 1
			end
		end
	end
	return result
end

--[[
	Sets a parameter value in the shared parameters table
	@param key: any - Parameter key
	@param value: any - Parameter value
]]
function StateMachine:SetParam(key: any, value: any)
	self.params[key] = value
end

--[[
	Adds a new transition to the state machine
	@param transition: Transition - Transition to add
]]
function StateMachine:AddTransition(transition: Transition)
	self:_registerTransitions({ transition })
end

--[[ PRIVATE METHODS ]]

--[[
	Validates configuration for correctness
	@param config: StateMachineConfig - Configuration to validate
	@throws Error if initial state is missing or transitions reference undefined states
]]
function StateMachine:_validateConfig(config: StateMachineConfig)
	if not config.states[config.initialState] then
		error(`Initial state '{config.initialState}' not found in states`)
	end

	if config.transitions ~= nil then
		for _, transition in config.transitions do
			local fromStates = type(transition.from) == "table" and transition.from or { transition.from }

			for _, fromState in fromStates do
				if fromState ~= "*" and not config.states[fromState] then
					error(`Transition from undefined state '${fromState}'`)
				end
				if not config.states[transition.to] then
					error(`Transition to undefined state '${transition.to}'`)
				end
			end
		end
	end
end

--[[
	Registers all states from the configuration
	@param states: {[string]: StateDefinition} - Table of state names to state definitions
	@throws Error if duplicate state names are detected
]]
function StateMachine:_registerStates(states: { [string]: StateDefinition })
	for name, state in states do
		if self.states[name] then
			error(`Duplicate state registration: '${name}'`)
		end

		local registeredState: State = {
			name = name,
			onEnter = state.onEnter or function() end,
			onExit = state.onExit or function() end,
			onUpdate = state.onUpdate or function() end,
			allowedTransitions = state.allowedTransitions, -- Explicit transition permissions
			params = self.params,
		}

		-- Copy additional state properties for extensibility
		for key, value in pairs(state) do
			if not registeredState[key] then
				registeredState[key] = value
			end
		end

		self.states[name] = registeredState
	end
end

--[[
	Registers and sorts transitions by priority
	@param transitions: {Transition}? - Optional list of transitions to register
]]
function StateMachine:_registerTransitions(transitions: { Transition }?)
	if transitions then
		-- Sort transitions by priority (highest first)
		table.sort(transitions, function(a, b)
			return (a.priority or 0) > (b.priority or 0)
		end)

		for _, transition in transitions do
			local fromStates = type(transition.from) == "table" and transition.from or { transition.from }

			for _, fromState in fromStates do
				self.fromTransitions[fromState] = self.fromTransitions[fromState] or {}
				table.insert(self.fromTransitions[fromState], transition)
			end
		end
	end
end

--[[
	Adds state to history using circular buffer
	@param state: State - State to add to history
]]
function StateMachine:_addToHistory(state: State)
	self._historyIndex = (self._historyIndex % self.historySize) + 1
	self.history[self._historyIndex] = state.name
end

return StateMachine
