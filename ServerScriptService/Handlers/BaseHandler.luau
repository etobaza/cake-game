-- Binds the player to their claimed pre-built bakery and tears the binding down on leave.
-- Nothing is cloned: anchors live in the reference bakery (BaseConfig.TemplateName) and are mapped
-- into the claimed one through the origin part transform. The artist's upgrade models in the bakery
-- are shown and hidden per the owner's purchases by UpgradeViewHandler, not here.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local DataHandler = require(_Handlers.DataHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local LoggerUtil = require(_Libs.Logger)
local PlotHandler = require(_Handlers.PlotHandler)
local Signal = require(_Libs.Signal)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "BaseHandler" })

--[[ Tables ]]--
local BaseHandler = {
	dependencies = { "DataHandler", "PlotHandler" },
}

export type PlayerBase = {
	Model: Folder,
	Janitor: any,
	-- Template -> world. Other systems translate their coordinates into the player's bakery through it.
	Transform: CFrame,
	Unloading: boolean?,
}

-- Fired after a player's bakery is claimed and owned.
BaseHandler.BaseReady = Signal() :: Signal.Signal<Player, Folder>
-- Fired before the bakery is released, while the binding is still valid.
BaseHandler.BaseRemoving = Signal() :: Signal.Signal<Player, Folder>

--[[ Private Functions ]]--
local function resolvePath(root: Instance, path: { string }): Instance?
	local current: Instance? = root

	for _, name in path do
		current = current and current:FindFirstChild(name)
	end

	return current
end

-- The part every bakery carries at the same authored spot; its CFrame defines the bakery's frame.
local function resolveOrigin(bakery: Instance): CFrame
	local part = resolvePath(bakery, BaseConfig.OriginPath)
	if not part or not part:IsA("BasePart") then
		error(`[BaseHandler] Missing origin part in {bakery:GetFullName()}.{table.concat(BaseConfig.OriginPath, ".")}`)
	end

	return part.CFrame
end

local function resolveTemplate(): Instance
	local bakeries = workspace:WaitForChild(BaseConfig.BakeriesFolderName)
	local template = bakeries:FindFirstChild(BaseConfig.TemplateName)
	if not template then
		error(
			`[BaseHandler] Template bakery not found: Workspace.{BaseConfig.BakeriesFolderName}.{BaseConfig.TemplateName}`
		)
	end

	return template
end

-- Floor point named in the template's Anchors folder.
local function resolveAnchor(template: Instance, anchorName: string): CFrame?
	local folder = template:FindFirstChild(BaseConfig.AnchorsFolderName)
	local part = folder and folder:FindFirstChild(anchorName)

	return if part and part:IsA("BasePart") then part.CFrame else nil
end

local function requireAnchor(template: Instance, anchorName: string): CFrame
	local anchor = resolveAnchor(template, anchorName)
	if not anchor then
		error(`[BaseHandler] Missing anchor {anchorName} in {template:GetFullName()}.{BaseConfig.AnchorsFolderName}`)
	end

	return anchor
end

local function resolveSignLabel(bakery: Instance): TextLabel?
	local sign = resolvePath(bakery, BaseConfig.SignPath)
	local surface = sign and sign:FindFirstChildWhichIsA("SurfaceGui", true)
	local label = surface and surface:FindFirstChildWhichIsA("TextLabel", true)

	return label :: TextLabel?
end

-- Puts the owner's name on the board over the door. The text it replaces is read off the instance,
-- so the sign goes back to exactly what the artist wrote when the bakery is released.
local function labelSign(bakery: Instance, player: Player, baseJanitor: any): ()
	local label = resolveSignLabel(bakery)
	if not label then
		Logger:Warn(`No sign label in {bakery.Name}`)
		return
	end

	local vacant = label.Text
	label.Text = string.format(BaseConfig.SignOwnedFormat, player.DisplayName)

	baseJanitor:Add(function()
		if label.Parent then
			label.Text = vacant
		end
	end, true)
end

local function teleportToBase(player: Player, template: Instance, transform: CFrame, isCurrent: () -> boolean): ()
	local character = player.Character
	if not character then
		return
	end

	if not character:FindFirstChild("HumanoidRootPart") then
		character:WaitForChild("HumanoidRootPart", BaseConfig.CharacterTimeout)
	end
	if not isCurrent() or player.Character ~= character or not character.Parent then
		return
	end

	character:PivotTo(
		transform * requireAnchor(template, BaseConfig.SpawnAnchorName) * CFrame.new(0, BaseConfig.CharacterLift, 0)
	)
end

--[[ Handling ]]--
function BaseHandler.OnInit(self: BaseHandler): ()
	self.Template = resolveTemplate()
	self.TemplateOrigin = resolveOrigin(self.Template)
	self.Bases = {}
end

function BaseHandler.OnStart(self: BaseHandler): ()
	-- A slow published-server profile load can outlive the initial join timeout.
	DataHandler.PlayerReady:Connect(function(player: Player)
		self:LoadBase(player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		self:LoadBase(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:LoadBase(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		self:UnloadBase(player)
	end)
end

-- Waits for the player data, claims a bakery and binds the player to it.
function BaseHandler.LoadBase(self: BaseHandler, player: Player): Folder?
	local existing = self.Bases[player]
	if existing then
		return existing.Model
	end

	if not DataHandler:WaitForPlayer(player, BaseConfig.DataTimeout) then
		Logger:Warn(`No data for {player.Name}, base not loaded`)
		return nil
	end

	if player.Parent ~= Players then
		return nil
	end
	-- Another caller can finish claiming while this call waits for the same profile.
	existing = self.Bases[player]
	if existing then
		return existing.Model
	end

	local bakery = PlotHandler:Claim(player)
	if not bakery then
		return nil
	end

	local transform = resolveOrigin(bakery) * self.TemplateOrigin:Inverse()
	bakery:SetAttribute(BaseConfig.OwnerAttribute, player.UserId)

	local baseJanitor = Janitor.new()
	labelSign(bakery, player, baseJanitor)

	local base: PlayerBase = { Model = bakery, Janitor = baseJanitor, Transform = transform }
	self.Bases[player] = base
	local function isCurrent(): boolean
		return player.Parent == Players and self.Bases[player] == base and not base.Unloading
	end

	baseJanitor:Add(
		player.CharacterAdded:Connect(function()
			teleportToBase(player, self.Template, transform, isCurrent)
		end),
		"Disconnect"
	)

	Logger:Info(`Base loaded for {player.Name} in {bakery.Name}`)
	self.BaseReady:Fire(player, bakery)
	task.spawn(teleportToBase, player, self.Template, transform, isCurrent)

	return bakery
end

-- Deferred observers restore authored models first; only then may another owner claim this plot.
function BaseHandler.UnloadBase(self: BaseHandler, player: Player): ()
	local base = self.Bases[player]
	if not base or base.Unloading then
		return
	end

	base.Unloading = true
	self.BaseRemoving:Fire(player, base.Model)
	task.defer(function()
		self.Bases[player] = nil
		base.Janitor:Destroy()
		base.Model:SetAttribute(BaseConfig.OwnerAttribute, nil)
		PlotHandler:Release(player)
		Logger:Info(`Base unloaded for {player.Name}`)
	end)
end

function BaseHandler.GetBase(self: BaseHandler, player: Player): Folder?
	local base = self.Bases[player]

	return base and base.Model
end

-- Template coordinate into the world: BuildingHandler places buildings around the bakery with it.
function BaseHandler.GetTransform(self: BaseHandler, player: Player): CFrame?
	local base = self.Bases[player]

	return base and base.Transform
end

function BaseHandler.GetAnchor(self: BaseHandler, anchorName: string): CFrame?
	return resolveAnchor(self.Template, anchorName)
end

-- How many `<prefix>_N` anchors exist, counting from 1 until a gap.
function BaseHandler.CountAnchors(self: BaseHandler, prefix: string): number
	local count = 0

	while resolveAnchor(self.Template, `{prefix}_{count + 1}`) do
		count += 1
	end

	return count
end

-- Base owner by any instance inside it.
function BaseHandler.GetOwnerOf(_self: BaseHandler, instance: Instance): Player?
	local current: Instance? = instance

	while current do
		local userId = current:GetAttribute(BaseConfig.OwnerAttribute)
		if userId then
			return Players:GetPlayerByUserId(userId :: number)
		end

		current = current.Parent
	end

	return nil
end

export type BaseHandler = typeof(BaseHandler) & {
	Template: Instance,
	TemplateOrigin: CFrame,
	Bases: { [Player]: PlayerBase },
}

return BaseHandler :: BaseHandler
