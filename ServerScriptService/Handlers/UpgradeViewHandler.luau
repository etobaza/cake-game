--!strict
-- Shows and hides the artist's upgrade models in a claimed bakery to match what the owner bought.
--
-- Every buyable thing has a folder in its zone's `Upgrades` folder, authored as:
--   BuildPlaceholder / BuildPlaceholderN -- the "under construction" spot shown before the buy
--   Upgrade / UpgradeN                   -- the bought look
--
-- Folders come in two shapes, because the artist drew two different things:
--   Slot   -- the folder stands at one anchor of a group (a tree, a bed, an animal, an oven). It
--             follows whether that anchor is filled, which is not the same as "how many are owned":
--             the shop order and the artist's layout differ (Buildings.Kinds.<Kind>.SlotOrder).
--   Level  -- the folder grows with one upgrade's level (the display counter, the cat cafe).
--
-- Mode "Reveal" swaps the placeholder for the artist's model. "PlaceholderOnly" only retires the
-- placeholder: the bought look is spawned by BuildingHandler (trees and beds), so showing
-- the artist copy too would stand one model inside another.
--
-- Authored state is snapshotted at claim and restored during teardown. PlotHandler then applies
-- the vacant appearance after deferred teardown observers finish.

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
local BaseHandler = require(_Handlers.BaseHandler)
local BuildingsConfig = require(_Configs.Buildings)
local DataHandler = require(_Handlers.DataHandler)
local LoggerUtil = require(_Libs.Logger)
local UpgradeHandler = require(_Handlers.UpgradeHandler)
local Upgrades = require(_Configs.Registries.Upgrades)

--[[ Constants ]]--
type ViewSpec = {
	Zone: string,
	Folder: string,
	Mode: "Reveal" | "PlaceholderOnly",
	-- Slot shape: the group this folder belongs to, and the anchor it stands at.
	Kind: string?,
	Slot: number?,
	-- One folder holding several slots: authored suffix -> anchor index ("Upgrade2" -> oven_2).
	SlotBySuffix: { [number]: number }?,
	-- Level shape: the upgrade whose level this folder follows.
	UpgradeId: string?,
	-- These authored models are replaced by runtime visuals; retain the surrounding upgrade.
	HiddenChildren: { string }?,
}

local VIEWS: { ViewSpec } = {
	--[[ Slot folders ]]--
	{ Zone = "Kitchen", Folder = "Freezer", Kind = "Freezer", Slot = 1, Mode = "Reveal" },
	{ Zone = "Cafe", Folder = "CoffeeMachine", Kind = "Coffee", Slot = 1, Mode = "Reveal" },
	-- The artist's two upgrade ovens: Upgrade1 stands at oven_3, Upgrade2 at oven_2.
	{
		Zone = "Kitchen",
		Folder = " OvenUpgrade",
		Kind = "Oven",
		SlotBySuffix = { [1] = 3, [2] = 2 },
		Mode = "Reveal",
	},
	-- GardenWorld owns source folders, including their placeholders and care variants.
	-- The second cafe table: the artist's own, drawn complete with its chair, cups, menus and the rug
	-- under it (the rug was moved into this folder so it goes with the table). Nothing is spawned for
	-- a table anywhere -- Kinds.Table is Hidden -- so this is the whole of what the upgrade shows.
	{ Zone = "Cafe", Folder = "TwoSeatsTable", Kind = "Table", Slot = 1, Mode = "Reveal" },

	--[[ Level folders ]]--
	{ Zone = "Cafe", Folder = "DisplayCounter", UpgradeId = "cafe_display", Mode = "Reveal" },
	{ Zone = "Cafe", Folder = "KitchenWindow", UpgradeId = "cafe_window", Mode = "Reveal" },
	{ Zone = "Cafe", Folder = "CatCafe", UpgradeId = "cafe_catcafe", Mode = "Reveal" },
	{ Zone = "Kitchen", Folder = "KitchenCounter", UpgradeId = "kitchen_counter", Mode = "Reveal" },
	{
		Zone = "Kitchen",
		Folder = "RailCart",
		UpgradeId = "garden_cart",
		Mode = "Reveal",
		HiddenChildren = { "Cart", "DeliveryCart1", "DeliveryCart2", "DeliveryCart3", "DeliveryCart4" },
	},
	{ Zone = "Garden", Folder = "CrystalWater", UpgradeId = "garden_water", Mode = "Reveal" },
	{ Zone = "Garden", Folder = "Sprinkler", UpgradeId = "garden_sprinkler", Mode = "Reveal" },
}

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "UpgradeViewHandler" })

--[[ Tables ]]--
local UpgradeViewHandler = {
	dependencies = { "DataHandler", "BaseHandler", "UpgradeHandler" },
}

type Saved = {
	Transparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
}

--[[ Private Functions ]]--
-- Authored suffix of a child: "Upgrade" and "BuildPlaceholder" read as 1.
local function SuffixOf(childName: string): (string?, number)
	local name, digits = childName:match("^(%a+)(%d*)$")

	return name, tonumber(digits) or 1
end

--[[ Handling ]]--
function UpgradeViewHandler.OnInit(self: UpgradeViewHandler): ()
	self.Saved = {}
end

function UpgradeViewHandler.OnStart(self: UpgradeViewHandler): ()
	BaseHandler.BaseReady:Connect(function(player: Player, bakery: Folder)
		self:Claim(player, bakery)
	end)

	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:Restore(player)
	end)

	UpgradeHandler.StatsChanged:Connect(function(player: Player)
		self:Apply(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:Restore(player)
	end)

	-- The base may have gone up before this handler subscribed to the signal.
	for _, player in Players:GetPlayers() do
		local bakery = BaseHandler:GetBase(player)
		if bakery then
			self:Claim(player, bakery)
		end
	end
end

-- Snapshots the authored look of every mapped part once per claim, then applies the owner's levels.
function UpgradeViewHandler.Claim(self: UpgradeViewHandler, player: Player, bakery: Folder): ()
	if self.Saved[player] then
		return
	end

	local saved: { [BasePart]: Saved } = {}

	for _, view in VIEWS do
		local folder = self:ResolveFolder(bakery, view)
		if not folder then
			continue
		end

		for _, piece in folder:GetDescendants() do
			if piece:IsA("BasePart") then
				saved[piece] = {
					Transparency = piece.Transparency,
					CanCollide = piece.CanCollide,
					CanQuery = piece.CanQuery,
				}
			end
		end
	end

	self.Saved[player] = saved
	self:Apply(player)
end

-- Whether the anchor `slot` of a group building is one of the ones the owner has filled. The Nth
-- purchase fills anchor SlotOrder[N], so owning two trees is not the same as owning anchors 1 and 2.
function UpgradeViewHandler.IsSlotFilled(
	_self: UpgradeViewHandler,
	player: Player,
	kindName: string,
	slot: number
): boolean
	local kind = BuildingsConfig.Kinds[kindName]
	if not kind or not kind.Stat then
		return false
	end

	local owned = UpgradeHandler:GetStat(player, kind.Stat :: any)
	local order = kind.SlotOrder
	if not order then
		return slot <= owned
	end

	for purchase = 1, math.min(owned, #order) do
		if order[purchase] == slot then
			return true
		end
	end

	return false
end

-- Repaints every mapped folder to what the owner has bought.
function UpgradeViewHandler.Apply(self: UpgradeViewHandler, player: Player): ()
	if not self.Saved[player] then
		return
	end

	local bakery = BaseHandler:GetBase(player)
	if not bakery then
		return
	end

	for _, view in VIEWS do
		local folder = self:ResolveFolder(bakery, view)
		if folder then
			self:ApplyFolder(player, folder, view)
		end
	end
end

function UpgradeViewHandler.ApplyFolder(self: UpgradeViewHandler, player: Player, folder: Instance, view: ViewSpec): ()
	local entry = view.UpgradeId and Upgrades:Get(view.UpgradeId)
	local level = if view.UpgradeId then self:GetLevel(player, view.UpgradeId) else 0

	for _, child in folder:GetChildren() do
		local name, suffix = SuffixOf(child.Name)
		if name ~= "Upgrade" and name ~= "BuildPlaceholder" then
			-- Anything the artist drew that is neither of those two stays out of an owned bakery.
			self:SetShown(player, child, false)
			continue
		end

		local bought: boolean
		if view.Kind then
			local slot = view.Slot or (view.SlotBySuffix and view.SlotBySuffix[suffix])
			bought = slot ~= nil and self:IsSlotFilled(player, view.Kind, slot :: number)
		else
			-- A numbered model is one level of the ladder; an unnumbered one is the whole upgrade.
			local step = if entry and entry.maxLevel > 1 then suffix else 1
			bought = level >= step
		end

		local reveal = view.Mode ~= "PlaceholderOnly"
		local visible = if name == "BuildPlaceholder" then not bought else (bought and reveal)

		self:SetShown(player, child, visible)
		if name == "Upgrade" and view.HiddenChildren then
			for _, model in child:GetChildren() do
				if table.find(view.HiddenChildren, model.Name) then
					self:SetShown(player, model, false)
				end
			end
		end
	end
end

function UpgradeViewHandler.GetLevel(_self: UpgradeViewHandler, player: Player, upgradeId: string): number
	local data = DataHandler:GetData(player)
	local levels = data and data.Cloud.Base.Upgrades

	return (levels and levels[upgradeId]) or 0
end

-- Writes the authored properties back; the bakery leaves exactly as the artist drew it.
function UpgradeViewHandler.Restore(self: UpgradeViewHandler, player: Player): ()
	local saved = self.Saved[player]
	if not saved then
		return
	end

	for part, entry in saved do
		if part.Parent then
			part.Transparency = entry.Transparency
			part.CanCollide = entry.CanCollide
			part.CanQuery = entry.CanQuery
		end
	end

	self.Saved[player] = nil
end

function UpgradeViewHandler.ResolveFolder(_self: UpgradeViewHandler, bakery: Folder, view: ViewSpec): Instance?
	local floor = bakery:FindFirstChild("1ndFloor")
	local zoneFolder = floor and floor:FindFirstChild(view.Zone)
	local upgrades = zoneFolder and zoneFolder:FindFirstChild("Upgrades")
	if not upgrades then
		return nil
	end

	local folder = upgrades:FindFirstChild(view.Folder)

	-- Some authored names carry stray spaces ("KitchenWindow "); match on the trimmed name too.
	if not folder then
		local wanted = view.Folder:match("^%s*(.-)%s*$")
		for _, child in upgrades:GetChildren() do
			if child.Name:match("^%s*(.-)%s*$") == wanted then
				folder = child
				break
			end
		end
	end

	if not folder then
		Logger:Warn(`No artist folder '{view.Folder}' in {bakery.Name}`)
	end

	return folder
end

-- Shows or hides one authored child without destroying anything. A shown part goes back to the
-- properties it was drawn with, so parts the artist drew invisible stay invisible.
function UpgradeViewHandler.SetShown(self: UpgradeViewHandler, player: Player, child: Instance, visible: boolean): ()
	local saved = self.Saved[player]
	if not saved then
		return
	end

	local pieces: { BasePart } = if child:IsA("BasePart") then { child } else {}
	for _, piece in child:GetDescendants() do
		if piece:IsA("BasePart") then
			table.insert(pieces, piece)
		end
	end

	for _, piece in pieces do
		local authored = saved[piece]

		if visible and authored then
			piece.Transparency = authored.Transparency
			piece.CanCollide = authored.CanCollide
			piece.CanQuery = authored.CanQuery
		elseif not visible then
			piece.Transparency = 1
			piece.CanCollide = false
			piece.CanQuery = false
		end
	end
end

export type UpgradeViewHandler = typeof(UpgradeViewHandler) & {
	Saved: { [Player]: { [BasePart]: Saved } },
}

return UpgradeViewHandler :: UpgradeViewHandler
