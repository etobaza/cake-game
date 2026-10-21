--!strict
-- The paid 2x coin boost (Configs/CashBoost). EconomyHandler applies the multiplier from
-- Session.CashBoostEndsAt; this handler keeps that end time and the banked seconds in step.
--
-- The time runs only while the player is in the game, the same way the playtime track does: on join
-- the banked Cloud.CashBoostSeconds becomes an end time, and on leave (and every SaveInterval) what is
-- left of it is banked again. A purchase adds Seconds to both.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local Config = require(_Configs.CashBoost)
local DataHandler = require(_Handlers.DataHandler)
local LoggerUtil = require(_Shared.Libs.Logger)
local Products = require(_Configs.Registries.Products)
local PurchaseHandler = require(_Handlers.PurchaseHandler)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "CashBoostHandler" })

--[[ Tables ]]--
local CashBoostHandler = {
	dependencies = { "DataHandler", "PurchaseHandler" },
}

--[[ Private Functions ]]--
local function now(): number
	return workspace:GetServerTimeNow()
end

--[[ Handling ]]--
function CashBoostHandler.OnStart(self: CashBoostHandler): ()
	local entry = Products:Get(Config.Product)
	if not entry then
		Logger:Warn(`Boost product {Config.Product} is missing from the registry`)
	end

	PurchaseHandler.PurchaseCompleted:Connect(function(player: Player, productId: number)
		if entry and entry.productId > 0 and productId == entry.productId then
			self:Add(player, Config.Seconds)
		end
	end)

	DataHandler.PlayerReady:Connect(function(player: Player)
		self:Resume(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataHandler:GetData(player) then
			self:Resume(player)
		end
	end

	DataHandler:OnLeaving(function(player: Player)
		self:Bank(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.SaveInterval)
			for _, player in Players:GetPlayers() do
				self:Bank(player)
			end
		end
	end)
end

--- Turns the banked seconds into this session's end time.
function CashBoostHandler.Resume(_self: CashBoostHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local banked = data.Cloud.CashBoostSeconds
	if typeof(banked) == "number" and banked > 0 then
		data.Session.CashBoostEndsAt = now() + banked
	end
end

--- Writes what is left of the running boost back to the profile.
function CashBoostHandler.Bank(_self: CashBoostHandler, player: Player): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end
	local endsAt = data.Session.CashBoostEndsAt
	if typeof(endsAt) ~= "number" or endsAt <= 0 then
		return
	end

	local left = math.max(0, math.floor(endsAt - now()))
	if data.Cloud.CashBoostSeconds ~= left then
		data.Cloud.CashBoostSeconds = left
	end
	if left == 0 then
		data.Session.CashBoostEndsAt = 0
	end
end

--- Adds boost time: on top of a running boost, or starting now.
function CashBoostHandler.Add(self: CashBoostHandler, player: Player, seconds: number): ()
	local data = DataHandler:GetData(player)
	if not data then
		return
	end

	local endsAt = data.Session.CashBoostEndsAt
	local from = if typeof(endsAt) == "number" and endsAt > now() then endsAt else now()
	data.Session.CashBoostEndsAt = from + seconds
	self:Bank(player)
	Logger:Info(`{player.Name} added {seconds}s of 2x cash`)
end

export type CashBoostHandler = typeof(CashBoostHandler)

return CashBoostHandler :: CashBoostHandler
