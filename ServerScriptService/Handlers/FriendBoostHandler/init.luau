--!strict
-- Server-owned active friendships; Session is a display mirror, never the income authority.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataHandler = require(ServerScriptService.Handlers.DataHandler)
local Friends = require(ReplicatedStorage.Shared.Configs.Friends)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Roster = require(script.Roster)

local FriendBoostHandler = {
	dependencies = { "DataHandler" },
	priority = 95,
}

function FriendBoostHandler.Publish(_self: FriendBoostHandler, player: Player, count: number): ()
	local data = DataHandler:GetData(player)
	if not data or player.Parent ~= Players then
		return
	end
	data.Session.FriendBoost.Count = count
	data.Session.FriendBoost.Percent = Friends.GetPercent(count)
end

function FriendBoostHandler.OnInit(self: FriendBoostHandler): ()
	self.Janitor = Janitor.new()
	self.Roster = Roster.new(function(first: Player, second: Player): boolean
		-- Studio's synthetic local players have no platform friendship records.
		if first.UserId <= 0 or second.UserId <= 0 then
			return false
		end
		return first:IsFriendsWithAsync(second.UserId)
	end, function(player: Player, count: number): ()
		self:Publish(player, count)
	end)
	self.Janitor:Add(self.Roster, "Destroy")
end

function FriendBoostHandler.OnStart(self: FriendBoostHandler): ()
	self.Janitor:Add(
		Players.PlayerAdded:Connect(function(player: Player): ()
			self.Roster:Add(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player): ()
			self.Roster:Remove(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		DataHandler.PlayerReady:Connect(function(player: Player): ()
			self:Publish(player, self.Roster:GetCount(player))
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		self.Roster:Add(player)
		self:Publish(player, self.Roster:GetCount(player))
	end
	local ticker = task.spawn(function(): ()
		while not self.Roster.Destroyed do
			task.wait(Friends.TickSeconds)
			self.Roster:Tick()
		end
	end)
	self.Janitor:Add(function(): ()
		task.cancel(ticker)
	end)
end

function FriendBoostHandler.GetMultiplier(self: FriendBoostHandler, player: Player): number
	return 1 + Friends.GetPercent(self.Roster:GetCount(player)) / 100
end

function FriendBoostHandler.Destroy(self: FriendBoostHandler): ()
	self.Janitor:Cleanup()
end

export type FriendBoostHandler = typeof(FriendBoostHandler) & {
	Janitor: any,
	Roster: Roster.Roster,
}

return FriendBoostHandler :: FriendBoostHandler
