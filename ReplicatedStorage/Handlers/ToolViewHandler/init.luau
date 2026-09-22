--!strict
-- Shared tool rendering follows the authoritative carried-appearance attribute for every player.
--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Config = require(ReplicatedStorage.Shared.Configs.ToolPresentation)
local Tool = require(script.Tool)

--[[ Constants ]]--
local BIND_NAME = "CakeHeldTools"
--[[ Tables ]]--
local ToolViewHandler = {}

--[[ Handling ]]--
function ToolViewHandler.OnInit(self: ToolViewHandler): ()
	self.Janitor = Janitor.new()
	self.Tools = {}
	self.Root = Instance.new("Folder")
	self.Root.Name = "HeldToolHost"
	self.Root.Parent = workspace
	self.Janitor:Add(self.Root, "Destroy")
end

function ToolViewHandler.Attach(self: ToolViewHandler, player: Player): ()
	if self.Tools[player] then
		return
	end
	local tool = Tool.new(player, self.Root)
	self.Tools[player] = tool
	self.Janitor:Add(tool, "Destroy", player)
end

function ToolViewHandler.Detach(self: ToolViewHandler, player: Player): ()
	self.Janitor:Remove(player)
	self.Tools[player] = nil
end

function ToolViewHandler.GetTool(self: ToolViewHandler, player: Player): BasePart?
	local tool = self.Tools[player]
	return tool and tool.Mesh
end

function ToolViewHandler.OnStart(self: ToolViewHandler): ()
	self.Janitor:Add(
		ReplicatedStorage.DescendantAdded:Connect(function(instance: Instance): ()
			if not instance:IsA("BasePart") then
				return
			end
			for _, tool in self.Tools do
				if tool.ToolId and not tool.Mesh then
					tool:Refresh()
				end
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerAdded:Connect(function(player: Player): ()
			self:Attach(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player): ()
			self:Detach(player)
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		self:Attach(player)
	end
	RunService:BindToRenderStep(BIND_NAME, Config.RenderPriority, function(): ()
		for _, tool in self.Tools do
			tool:Step()
		end
	end)
	self.Janitor:Add(function(): ()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end, true)
end

function ToolViewHandler.Destroy(self: ToolViewHandler): ()
	self.Janitor:Destroy()
	table.clear(self.Tools)
end

export type ToolViewHandler = typeof(ToolViewHandler) & { Janitor: any, Root: Folder, Tools: { [Player]: Tool.Tool } }
return ToolViewHandler :: ToolViewHandler
