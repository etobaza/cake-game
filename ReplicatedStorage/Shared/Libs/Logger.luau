--!strict
-- Logger.luau
-- Advanced logging system with configurable outputs and diagnostics
-- koi-code <3

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Logger = {}
Logger.__index = Logger

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL"
export type LogAppender = (logEntry: LogEntry) -> ()
export type LogEntry = {
	timestamp: number,
	level: LogLevel,
	message: string,
	tags: { string },
	stack: string?,
	source: string?,
	player: Player?,
	data: { [string]: any }?,
}

type LoggerConfig = {
	name: string,
	minLevel: LogLevel?,
	bufferSize: number?,
	enableColors: boolean?,
	logToRobloxOutput: boolean?,
	maxMessageLength: number?,
}

local LEVEL_COLORS = {
	DEBUG = Color3.fromRGB(100, 100, 100),
	INFO = Color3.fromRGB(0, 150, 255),
	WARN = Color3.fromRGB(255, 200, 0),
	ERROR = Color3.fromRGB(255, 50, 50),
	FATAL = Color3.fromRGB(150, 0, 0),
}

local LEVEL_WEIGHTS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5 }

function Logger.new(config: LoggerConfig)
	local self = setmetatable({
		_name = config.name,
		_buffer = {},
		_appenders = {},
		_config = {
			minLevel = config.minLevel or (RunService:IsStudio() and "DEBUG" or "INFO"),
			bufferSize = config.bufferSize or 100,
			logToRobloxOutput = config.logToRobloxOutput or true,
			maxMessageLength = config.maxMessageLength or 1000,
		},
		_enabled = true,
		_player = nil,
	}, Logger)

	self:_initDefaultAppenders()
	return self
end

--[[ Private Methods ]]
function Logger:_initDefaultAppenders()
	-- Console appender
	self:AddAppender(function(entry)
		if self._config.logToRobloxOutput then
			local message = self:_formatMessage(entry)
			if entry.level == "ERROR" or entry.level == "FATAL" then
				task.spawn(function()
					error(message)
				end)
			else
				print(message)
			end
		end
	end)
end

function Logger:_shouldLog(level: LogLevel)
	return LEVEL_WEIGHTS[level] >= LEVEL_WEIGHTS[self._config.minLevel]
end

function Logger:_formatMessage(entry: LogEntry)
	-- Format timestamp
	local timeString = os.date("%H:%M:%S", entry.timestamp)

	-- Format tags
	local tags = ""
	if #entry.tags > 0 then
		tags = " [" .. table.concat(entry.tags, "][") .. "]"
	end

	-- Format player info
	local playerInfo = ""
	if entry.player then
		playerInfo = string.format(" %s:%d", entry.player.Name, entry.player.UserId)
	end

	-- Format data context
	local dataContext = ""
	if entry.data then
		dataContext = " | " .. HttpService:JSONEncode(entry.data)
	end

	-- Build final message
	local message = string.format(
		"%-5s%s%s%s: %s%s",
		`[{entry.source}::{entry.level}] `,
		timeString :: string,
		tags,
		playerInfo,
		entry.message,
		dataContext
	)

	-- Truncate if needed
	return string.sub(message, 1, self._config.maxMessageLength)
end

--[[ Public Methods ]]
function Logger:AddAppender(appender: LogAppender)
	table.insert(self._appenders, appender)
end

function Logger:SetPlayer(player: Player)
	self._player = player
end

function Logger:WithPlayer(player: Player)
	local copy = setmetatable(table.clone(self), Logger)
	copy._player = player
	return copy
end

function Logger:EnableDebugMode()
	self._config.minLevel = "DEBUG"
end

function Logger:Log(level: LogLevel, message: string, tags: { string }?, data: { [string]: any }?)
	if not self._enabled or not self:_shouldLog(level) then
		return
	end

	local logEntry = {
		timestamp = os.time(),
		level = level,
		message = message,
		tags = tags or {},
		stack = debug.traceback(),
		source = self._name,
		player = self._player,
		data = data,
		levelColor = LEVEL_COLORS[level],
	}

	-- Add to rolling buffer
	table.insert(self._buffer, 1, logEntry)
	if #self._buffer > self._config.bufferSize then
		table.remove(self._buffer)
	end

	-- Call appenders
	for _, appender in self._appenders do
		local success, err = pcall(appender, logEntry)
		if not success then
			print("Logger appender error:", err)
		end
	end
end

--[[ Log Level Shortcuts ]]
function Logger:Debug(message: string, tags: { string }?, data: { [string]: any }?)
	self:Log("DEBUG", message, tags, data)
end

function Logger:Info(message: string, tags: { string }?, data: { [string]: any }?)
	self:Log("INFO", message, tags, data)
end

function Logger:Warn(message: string, tags: { string }?, data: { [string]: any }?)
	self:Log("WARN", message, tags, data)
end

function Logger:Error(message: string, tags: { string }?, data: { [string]: any }?)
	self:Log("ERROR", message, tags, data)
end

function Logger:Fatal(message: string, tags: { string }?, data: { [string]: any }?)
	self:Log("FATAL", message, tags, data)
end

function Logger:Destroy()
	self._enabled = false
	self._buffer = {}
	self._appenders = {}
end

return Logger
