--[[
Crystal.luau Framework
Version 1.3.0

Created by codebykoi <3
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LoggerUtil = require(ReplicatedStorage.Shared.Libs.Logger)
local Promise = require(ReplicatedStorage.Packages["typed-promise"])

local Logger = LoggerUtil.new({ name = "Crystal" })

local Crystal = {}
Crystal.__index = Crystal

local HANDLERS = {}
local INSTANCES = {}
local TOPOLOGICAL_ORDER: any = {}
local MIDDLEWARE = {}

-- Lifecycle / metadata keys must not be middleware-proxied.
local SKIP_PROXY: { [string]: boolean } = {
	OnInit = true,
	OnStart = true,
}

local function isCrystalProxy(value: any): boolean
	local ok, result = pcall(function()
		local mt = getmetatable(value)
		if typeof(mt) ~= "table" then
			return false
		end
		if mt.__isCrystalProxy == true then
			return true
		end
		local index = mt.__index
		return typeof(index) == "table" and index.__isCrystalProxy == true
	end)
	return ok and result == true
end

local function buildDependencyGraph()
	local graph = {}
	local inDegree = {}

	for name in pairs(HANDLERS) do
		graph[name] = {}
		inDegree[name] = 0
	end

	for name, handler in pairs(HANDLERS) do
		local deps = handler.dependencies or {}
		for _, depName in ipairs(deps) do
			if not HANDLERS[depName] then
				error(`Missing dependency: '{depName}' required by handler '{name}'`)
			end
			table.insert(graph[depName], name)
			inDegree[name] += 1
		end
	end

	return graph, inDegree
end

local function getTableSize(t): number
	local k = 0
	for _ in t do
		k += 1
	end
	return k
end

-- Insert into queue sorted by priority (highest first).
local function insertByPriority(queue: { string }, name: string)
	local priority = HANDLERS[name].priority or 0
	local inserted = false

	for i, queueName in ipairs(queue) do
		local queuePriority = HANDLERS[queueName].priority or 0
		if priority > queuePriority then
			table.insert(queue, i, name)
			inserted = true
			break
		end
	end

	if not inserted then
		table.insert(queue, name)
	end
end

local function topologicalSort()
	local graph, inDegree = buildDependencyGraph()
	local queue = {}
	local result = {}
	local count = 0

	for name, degree in pairs(inDegree) do
		if degree == 0 then
			insertByPriority(queue, name)
		end
	end

	while #queue > 0 do
		local name = table.remove(queue, 1)
		table.insert(result, HANDLERS[name])
		count += 1

		local newReady = {}
		for _, dependent in ipairs(graph[name]) do
			inDegree[dependent] -= 1
			if inDegree[dependent] == 0 then
				table.insert(newReady, dependent)
			end
		end

		for _, dependent in ipairs(newReady) do
			insertByPriority(queue, dependent)
		end
	end

	if count < getTableSize(HANDLERS) then
		error("Circular dependency detected in handlers")
	end

	return result
end

local function proxifyMethod(handlerDef: any, methodName: string, func: (...any) -> ...any)
	local originalMethod = func

	local proxy = newproxy(true)
	local proxyMeta = getmetatable(proxy)

	-- Flag on the metatable itself so checks do not rely on __index lookup quirks.
	proxyMeta.__isCrystalProxy = true
	proxyMeta.__original = originalMethod
	proxyMeta.__index = {
		__isCrystalProxy = true,
		__original = originalMethod,
	}

	proxyMeta.__call = function(_, ...)
		local currentIndex = 0

		local function runNext(...)
			currentIndex += 1

			if currentIndex <= #MIDDLEWARE then
				return MIDDLEWARE[currentIndex](runNext, handlerDef.name, methodName, ...)
			else
				local results = table.pack(pcall(originalMethod, ...))
				if not results[1] then
					error(results[2])
				end
				return table.unpack(results, 2, results.n)
			end
		end

		return runNext(...)
	end

	handlerDef[methodName] = proxy
end

--[[ Public API ]]
--- Registers a new handler module
function Crystal.Register(module: ModuleScript)
	local handlerDef = require(module)

	handlerDef.name = handlerDef.name or module.Name

	if HANDLERS[handlerDef.name] then
		error(`Handler '{handlerDef.name}' already registered`)
	end

	if handlerDef.disabled then
		return
	end

	if handlerDef.studioOnly then
		if not RunService:IsStudio() then
			return
		end
	end

	if handlerDef.OnInit then
		assert(typeof(handlerDef.OnInit) == "function", "OnInit must be function")
	end
	if handlerDef.OnStart then
		assert(typeof(handlerDef.OnStart) == "function", "OnStart must be function")
	end

	if handlerDef.type == nil then
		handlerDef.type = if RunService:IsClient() then "Client" else "Server"
	end

	for methodName, func in handlerDef do
		if typeof(func) == "function" and not SKIP_PROXY[methodName] then
			if not isCrystalProxy(func) then
				proxifyMethod(handlerDef, methodName, func)
			end
		end
	end

	HANDLERS[handlerDef.name] = handlerDef
	Logger:Info(`Registered handler: {handlerDef.name} (Type: {handlerDef.type})`)

	TOPOLOGICAL_ORDER = nil
end

--- Initializes all handlers in dependency order.
--- Failed OnInit aborts boot so dependents never start against broken state.
local function initAll()
	if not TOPOLOGICAL_ORDER then
		TOPOLOGICAL_ORDER = topologicalSort()
	end

	Logger:Debug("Initializing handlers in topological order")

	for _, handler in TOPOLOGICAL_ORDER do
		if not INSTANCES[handler.name] then
			INSTANCES[handler.name] = handler

			if handler.OnInit then
				Logger:Debug(`Initializing {handler.name}`)
				local success, err = pcall(handler.OnInit, handler)
				if not success then
					error(`Failed initializing {handler.name}: {err}`)
				end
			end
		end
	end
end

--- Starts all handlers after initialization.
--- OnStart runs in topological order and is awaited so dependencies finish before dependents.
local function startAll()
	if not TOPOLOGICAL_ORDER then
		error("Handlers not initialized. Call Crystal.InitAll() first")
	end

	Logger:Debug("Starting handlers in topological order")

	for _, handler in TOPOLOGICAL_ORDER do
		if handler.OnStart then
			Logger:Debug(`Starting {handler.name}`)
			local instance = INSTANCES[handler.name]
			local success, err = pcall(handler.OnStart, instance)
			if not success then
				error(`Failed starting {handler.name}: {err}`)
			end
		end
	end
end

--- Registers a framework level middleware that intercepts ALL handler method calls
function Crystal.AddMiddleware(middleware: (
	next: (...any) -> ...any,
	handlerName: string,
	methodName: string,
	...any
) -> ...any)
	assert(typeof(middleware) == "function", "Middleware must be a function")
	table.insert(MIDDLEWARE, middleware)
end

Crystal.Run = Promise.promisify(function()
	initAll()
	startAll()
end)

return Crystal
