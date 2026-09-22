-- Collision groups of the game: registers them and puts player characters and room decorations
-- into theirs. What passes through what is decided in Configs/Collision, not here.

--[[ Services ]]--
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local BaseHandler = require(_Handlers.BaseHandler)
local CollisionConfig = require(_Configs.Collision)
local BuildingsConfig = require(_Configs.Buildings)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local World = require(_Shared.World)

--[[ Tables ]]--
local CollisionHandler = {
	dependencies = { "BaseHandler" },
	-- Ahead of everything that builds parts, though the groups themselves are already registered in
	-- the init phase: a part naming an unregistered group is an error, not a warning.
	priority = 90,
}

--[[ Handling ]]--
function CollisionHandler.OnInit(self: CollisionHandler): ()
	self.BaseJanitors = {}
	for _, group in CollisionConfig.Groups do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end

	for _, pair in CollisionConfig.Passable do
		PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
	end
end

function CollisionHandler.OnStart(self: CollisionHandler): ()
	self:OpenDoors()

	Players.PlayerAdded:Connect(function(player: Player)
		self:WatchCharacter(player)
	end)

	for _, player in Players:GetPlayers() do
		self:WatchCharacter(player)
	end

	BaseHandler.BaseReady:Connect(function(player: Player, root: Folder)
		self:OpenBase(player, root)
	end)
	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:CloseBase(player)
	end)

	-- A base may have gone up before this handler subscribed.
	for _, player in Players:GetPlayers() do
		local model = BaseHandler:GetBase(player)
		if model then
			self:OpenBase(player, model)
		end
	end
end

function CollisionHandler.WatchCharacter(self: CollisionHandler, player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		self:Apply(character, CollisionConfig.Groups.Player)
	end)

	if player.Character then
		self:Apply(player.Character, CollisionConfig.Groups.Player)
	end
end

-- Doors are the doorway, not something beside it: their slab fills the opening and never swings, so
-- a player or a guest has to walk straight through. Done for EVERY bakery once at boot rather than
-- per claimed base — an unclaimed bakery still has to be walkable to reach.
function CollisionHandler.OpenDoors(self: CollisionHandler): ()
	local bakeries = World.Bakeries()
	if not bakeries then
		return
	end

	for _, piece in bakeries:GetDescendants() do
		if piece:IsA("Model") and table.find(CollisionConfig.PassableModels, string.lower(piece.Name)) then
			self:Apply(piece, CollisionConfig.Groups.Door)
		end
	end
end

-- Decorations of the bakery are furniture, not walls: guests walk through them. The bakery keeps
-- one folder of that name per zone, so every matching folder in the tree joins the group.
function CollisionHandler.OpenBase(self: CollisionHandler, player: Player, root: Instance): ()
	self:CloseBase(player)
	local janitor = Janitor.new()
	self.BaseJanitors[player] = janitor
	local saved: { [BasePart]: string } = {}
	local function apply(holder: Instance): ()
		for _, piece in holder:GetDescendants() do
			if not piece:IsA("BasePart") or piece.CollisionGroup == CollisionConfig.Groups.Door then
				continue
			end
			saved[piece] = saved[piece] or piece.CollisionGroup
			piece.CollisionGroup = CollisionConfig.Groups.Prop
		end
	end
	janitor:Add(function()
		for part, group in saved do
			if part.Parent then
				part.CollisionGroup = group
			end
		end
	end, true)
	for _, piece in root:GetDescendants() do
		if piece:IsA("Folder") and table.find(CollisionConfig.PassableFolders, piece.Name) then
			apply(piece)
		end
	end
	for _, path in CollisionConfig.PassablePaths do
		local holder = BuildingsConfig.ResolvePath(root, path)
		if holder then
			apply(holder)
		end
	end
end

function CollisionHandler.CloseBase(self: CollisionHandler, player: Player): ()
	local janitor = self.BaseJanitors[player]
	if janitor then
		janitor:Destroy()
	end
	self.BaseJanitors[player] = nil
end

function CollisionHandler.Apply(_self: CollisionHandler, root: Instance, group: string): ()
	for _, piece in root:GetDescendants() do
		-- A door keeps the group it was given at boot: the kitchen arches sit inside Decoration, and
		-- the prop pass runs over the very same parts when a base is claimed.
		if piece:IsA("BasePart") and piece.CollisionGroup ~= CollisionConfig.Groups.Door then
			piece.CollisionGroup = group
		end
	end
end

export type CollisionHandler = typeof(CollisionHandler) & {
	BaseJanitors: { [Player]: any },
}

return CollisionHandler :: CollisionHandler
