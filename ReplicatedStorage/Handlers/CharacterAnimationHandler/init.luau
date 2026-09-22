--!strict
-- Owns the local character's animation session. Its server-created Animator replicates tracks.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Character = require(script.Character)
local DataClient = require(ReplicatedStorage.Handlers.DataHandlerClient)

--[[ Tables ]]--
local CharacterAnimationHandler = {
	-- Mixing follows the server-owned station snapshot, including late boot and respawn.
	dependencies = { "DataClient" },
}

--[[ Handling ]]--
function CharacterAnimationHandler.OnInit(self: CharacterAnimationHandler): ()
	self.Janitor = Janitor.new()
	self.Mixing = false
end

function CharacterAnimationHandler.Attach(self: CharacterAnimationHandler, model: Model): ()
	self:Detach()
	local character = Character.new(Players.LocalPlayer, model)
	character:SetMixing(self.Mixing)
	self.Character = character
end

function CharacterAnimationHandler.RefreshMixing(self: CharacterAnimationHandler): ()
	local mixing = false
	for _, station in DataClient:GetData({ "Stations" }, "Session") or {} do
		if station.Kind == "Mixer" and station.State == "Mixing" then
			mixing = true
			break
		end
	end
	self.Mixing = mixing
	if self.Character then
		self.Character:SetMixing(mixing)
	end
end

function CharacterAnimationHandler.Detach(self: CharacterAnimationHandler): ()
	if self.Character then
		self.Character:Destroy()
	end
	self.Character = nil
end

function CharacterAnimationHandler.OnStart(self: CharacterAnimationHandler): ()
	DataClient:WaitForData()
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Stations" }, function(): ()
			self:RefreshMixing()
		end, "Session", true),
		"Disconnect"
	)
	self:RefreshMixing()
	local player = Players.LocalPlayer
	self.Janitor:Add(
		player.CharacterAdded:Connect(function(model: Model): ()
			self:Attach(model)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		player.CharacterRemoving:Connect(function(): ()
			self:Detach()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Bus.Player.PlayAction.OnClientEvent:Connect(function(action: string): ()
			if self.Character then
				self.Character:PlayAction(action)
			end
		end),
		"Disconnect"
	)
	if player.Character then
		self:Attach(player.Character)
	end
end

function CharacterAnimationHandler.Destroy(self: CharacterAnimationHandler): ()
	self.Janitor:Destroy()
	self:Detach()
end

export type CharacterAnimationHandler = typeof(CharacterAnimationHandler) & {
	Janitor: any,
	Character: Character.Character?,
	Mixing: boolean,
}

return CharacterAnimationHandler :: CharacterAnimationHandler
