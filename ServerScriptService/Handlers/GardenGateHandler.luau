--!strict
-- Boards up the greenhouse arch of a claimed bakery until its owner buys anything that lives in the
-- greenhouse: a Greenhouse upgrade, or an animal kept there (Garden.Sources). A sign on the boards
-- names the cheapest such purchase the owner can buy right now. The boards come down on that buy and
-- with the bakery's release.

--[[ Services ]]--
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
local DataHandler = require(_Handlers.DataHandler)
local Format = require(_Shared.UI.Format)
local Garden = require(_Configs.Garden)
local GardenGate = require(_Configs.GardenGate)
local UIText = require(_Configs.UIText)
local UpgradeHandler = require(_Handlers.UpgradeHandler)
local Upgrades = require(_Configs.Registries.Upgrades)

--[[ Constants ]]--
-- Every purchase that puts something in the greenhouse.
local OPENERS: { string } = {}
do
	local seen: { [string]: boolean } = {}
	for id, entry in Upgrades:GetAll() do
		if entry.category == "Garden" then
			seen[id] = true
		end
	end
	for _, source in Garden.Sources do
		seen[source.Upgrade] = true
	end
	for id in seen do
		table.insert(OPENERS, id)
	end
	table.sort(OPENERS)
end

--[[ Tables ]]--
local GardenGateHandler = {
	dependencies = { "DataHandler", "BaseHandler", "UpgradeHandler" },
}

--[[ Private Functions ]]--
local function readLevels(player: Player): { [string]: number }?
	local data = DataHandler:GetData(player)
	return data and data.Cloud.Base.Upgrades
end

local function isOpen(levels: { [string]: number }): boolean
	for _, id in OPENERS do
		if (levels[id] or 0) > 0 then
			return true
		end
	end
	return false
end

-- The cheapest opener whose tree parents are owned, so the sign never names a locked node.
local function cheapestOpener(levels: { [string]: number }): (string?, number?)
	local bestId: string?, bestCost: number? = nil, nil
	for _, id in OPENERS do
		local entry = Upgrades:Get(id)
		if not entry or Upgrades:GetMissingRequirement(entry, levels) then
			continue
		end
		local cost = Upgrades:GetCost(id, levels[id] or 0)
		if cost and (not bestCost or cost < bestCost) then
			bestId, bestCost = id, cost
		end
	end
	return bestId, bestCost
end

local function makePart(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Material = GardenGate.Material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeLabel(name: string, text: string, size: UDim2, position: UDim2, parent: Instance): ()
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = GardenGate.Sign.Font
	label.TextColor3 = GardenGate.Sign.TextColor
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text
	label.Parent = parent
end

-- Builds the boards, the blocker and the sign, already in place, outside the DataModel.
local function build(gate: CFrame): Model
	local model = Instance.new("Model")
	model.Name = GardenGate.Name

	-- Named like the shell's wall folders so WallReach also stops prompts behind the boards.
	local wall = Instance.new("Folder")
	wall.Name = CollisionConfig.WallFolders[1]
	wall.Parent = model
	local blocker = makePart("Blocker", GardenGate.Blocker.Size, gate * CFrame.new(GardenGate.Blocker.Offset), wall)
	blocker.Transparency = 1
	blocker.CanQuery = true

	for index, board in GardenGate.Boards do
		local cframe = gate * CFrame.new(board.Offset) * CFrame.Angles(0, 0, math.rad(board.Roll))
		local part = makePart(`Board{index}`, board.Size, cframe, model)
		part.Color = board.Color
		part.CanCollide = false
	end

	local spec = GardenGate.Sign
	local sign = makePart("Sign", spec.Size, gate * CFrame.new(spec.Offset), model)
	sign.Color = spec.Color
	sign.CanCollide = false
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Text"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = spec.PixelsPerStud
	surface.LightInfluence = 0.5
	surface.Parent = sign
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = surface
	makeLabel("Title", UIText.GardenGate.Title, UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0), surface)
	makeLabel("Unlock", "", UDim2.fromScale(1, 0.52), UDim2.fromScale(0, 0.48), surface)

	model.PrimaryPart = blocker
	return model
end

--[[ Handling ]]--
function GardenGateHandler.OnInit(self: GardenGateHandler): ()
	self.Gates = {}
end

function GardenGateHandler.OnStart(self: GardenGateHandler): ()
	BaseHandler.BaseReady:Connect(function(player: Player)
		self:Apply(player)
	end)

	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:Remove(player)
	end)

	UpgradeHandler.StatsChanged:Connect(function(player: Player)
		self:Apply(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:Remove(player)
	end)

	-- The base may have gone up before this handler subscribed to the signal.
	for _, player in Players:GetPlayers() do
		self:Apply(player)
	end
end

-- Boards the arch while nothing in the greenhouse is owned, and keeps the sign's purchase current.
function GardenGateHandler.Apply(self: GardenGateHandler, player: Player): ()
	local bakery = BaseHandler:GetBase(player)
	local transform = BaseHandler:GetTransform(player)
	local levels = readLevels(player)
	if not bakery or not transform or not levels or isOpen(levels) then
		self:Remove(player)
		return
	end

	local current = self.Gates[player]
	local gate: Model
	if current and current.Parent == bakery then
		gate = current
	else
		self:Remove(player)
		gate = build(transform * GardenGate.Template)
		gate.Parent = bakery
		self.Gates[player] = gate
	end

	local id, cost = cheapestOpener(levels)
	local entry = id and Upgrades:Get(id)
	local label = gate:FindFirstChild("Unlock", true)
	if label and label:IsA("TextLabel") then
		label.Text = if entry and cost
			then string.format(UIText.GardenGate.Unlock, Upgrades:GetDisplayName(entry.id, levels[entry.id] or 0), Format.Number(cost))
			else ""
	end
end

function GardenGateHandler.Remove(self: GardenGateHandler, player: Player): ()
	local gate = self.Gates[player]
	if gate then
		gate:Destroy()
		self.Gates[player] = nil
	end
end

export type GardenGateHandler = typeof(GardenGateHandler) & {
	Gates: { [Player]: Model },
}

return GardenGateHandler :: GardenGateHandler
