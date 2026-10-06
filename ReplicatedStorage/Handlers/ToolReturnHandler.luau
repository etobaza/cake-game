--!strict
-- While the local player carries a rack tool (any building kind with a ToolId), the rack's own
-- model (hidden by the server) is shown as a local outline, and the hint arrow beam leads back
-- to it.

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local BuildingsConfig = require(_Configs.Buildings)
local Config = require(_Configs.ToolReturn)
local DataClient = require(script.Parent.DataHandlerClient)
local HintBeam = require(_Shared.UI.HintBeam)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local TutorialHandler = require(script.Parent.TutorialHandler)

--[[ Constants ]]--
local TOOL = "Tool"
-- The only children a copied part keeps: a mesh shapes the outline. Textures, surface appearances,
-- prompts, scripts and attachments stay on the original.
local SHAPE = "DataModelMesh"

--[[ Tables ]]--
local ToolReturnHandler = {
	dependencies = { "DataClient", "TutorialHandler" },
}

--[[ Private Functions ]]--
-- Kind name of the rack giving this tool, if any.
local function kindFor(toolId: string): string?
	for kindName, kind in BuildingsConfig.Kinds do
		if kind.ToolId == toolId then
			return kindName
		end
	end
	return nil
end

local function heldKind(hands: { any }?): string?
	if not hands then
		return nil
	end
	for _, item in hands do
		if item.Kind == TOOL then
			local kindName = kindFor(item.Id)
			if kindName then
				return kindName
			end
		end
	end
	return nil
end

-- The local player's rack prop of this kind.
local function findRack(kindName: string): BasePart?
	local userId = Players.LocalPlayer.UserId
	for _, part in CollectionService:GetTagged(BuildingsConfig.Tag) do
		if
			part:IsA("BasePart")
			and part:GetAttribute(BuildingsConfig.KindAttribute) == kindName
			and part:GetAttribute(BaseConfig.OwnerAttribute) == userId
		then
			return part
		end
	end
	return nil
end

local function copyPart(source: BasePart, parent: Instance): ()
	local copy = source:Clone()
	for _, child in copy:GetDescendants() do
		if not child:IsA(SHAPE) and child.Parent then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide, copy.CanQuery, copy.CanTouch = false, false, false
	copy.CastShadow = false
	-- The server hid the original. See Configs/ToolReturn for why the copy is glass.
	copy.Material = Config.GhostMaterial
	copy.Transparency = Config.GhostTransparency
	copy.Parent = parent
end

-- Parts that carry the rack's look: the authored world model, else the furniture hung on the
-- prompt block (the block itself is an invisible anchor), else the plain block.
local function lookParts(rack: BasePart): { BasePart }
	local source = BuildingsConfig.WorldModel(rack)
	local parts: { BasePart } = {}
	if source and source:IsA("BasePart") then
		table.insert(parts, source)
	end
	for _, piece in (source or rack):GetDescendants() do
		if piece:IsA("BasePart") then
			table.insert(parts, piece)
		end
	end
	if #parts == 0 and not source then
		table.insert(parts, rack)
	end
	return parts
end

local function buildGhost(rack: BasePart): Model
	local ghost = Instance.new("Model")
	ghost.Name = "ToolReturnGhost"

	for _, part in lookParts(rack) do
		copyPart(part, ghost)
	end

	local outline = Instance.new("Highlight")
	outline.Adornee = ghost
	outline.FillColor = Config.FillColor
	outline.FillTransparency = Config.FillTransparency
	outline.OutlineColor = Config.OutlineColor
	outline.OutlineTransparency = Config.OutlineTransparency
	outline.DepthMode = Config.DepthMode
	outline.Parent = ghost

	ghost.Parent = workspace
	return ghost
end

--[[ Handling ]]--
function ToolReturnHandler.OnStart(self: ToolReturnHandler): ()
	self.Janitor = Janitor.new()
	self.Beam = HintBeam.new()
	self.Janitor:Add(self.Beam, "Destroy")

	DataClient:WaitForData()

	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Hands" }, function(): ()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
	-- The rack prop may stream in after the tool was taken.
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(BuildingsConfig.Tag):Connect(function(): ()
			if self.Kind and not self.Ghost then
				self:Refresh()
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		RunService.RenderStepped:Connect(function(): ()
			self:Step()
		end),
		"Disconnect"
	)
	self:Refresh()
end

function ToolReturnHandler.Refresh(self: ToolReturnHandler): ()
	local kindName = heldKind(DataClient:GetData({ "Hands" }, "Session"))
	if kindName == self.Kind and (self.Ghost or not kindName) then
		return
	end

	self.Janitor:Remove("Ghost")
	self.Ghost = nil
	self.Kind = kindName
	if not kindName then
		return
	end

	local rack = findRack(kindName)
	if not rack then
		return
	end
	local ghost = buildGhost(rack)
	self.Ghost = ghost
	self.Janitor:Add(ghost, "Destroy", "Ghost")
end

function ToolReturnHandler.Step(self: ToolReturnHandler): ()
	local ghost = self.Ghost
	-- The tutorial owns the player's attention while it shows a goal: no outline, no second beam.
	local guiding = TutorialHandler.Guiding == true
	local outline = ghost and ghost:FindFirstChildOfClass("Highlight")
	if outline then
		outline.Enabled = not guiding
	end
	if not ghost or not ghost.Parent or guiding then
		self.Beam:Hide()
		return
	end
	self.Beam:Show(ghost:GetPivot().Position)
end

function ToolReturnHandler.Destroy(self: ToolReturnHandler): ()
	self.Janitor:Destroy()
	self.Ghost = nil
	self.Kind = nil
end

export type ToolReturnHandler = typeof(ToolReturnHandler) & {
	Janitor: any,
	Beam: HintBeam.View,
	Ghost: Model?,
	Kind: string?,
}

return ToolReturnHandler :: ToolReturnHandler
