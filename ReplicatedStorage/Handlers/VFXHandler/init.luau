--!strict
-- One client visual clock for authored effects; only the server announces successful actions.
--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.VFX)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Tools = require(ReplicatedStorage.Handlers.ToolViewHandler)
local Character = require(script.Character)
local Effect = require(script.Effect)
local Target = require(script.Target)

--[[ Constants ]]--
local BIND_NAME = "CakeVFX"
type Burst = { Visual: Effect.Effect, Part: BasePart?, Guard: BasePart?, GuardOwner: any, Frame: CFrame, Owner: number }
--[[ Tables ]]--
local VFXHandler = {
	-- Tool meshes must be available before nozzle/sweep effects resolve their holders.
	dependencies = { "ToolViewHandler" },
}

--[[ Handling ]]--
function VFXHandler.OnInit(self: VFXHandler): ()
	self.Janitor = Janitor.new()
	self.Targets, self.Characters, self.Bursts, self.Templates = {}, {}, {}, {}
	self.Root = Instance.new("Folder")
	self.Root.Name = "VFXVisuals"
	self.Root.Parent = workspace
	self.Janitor:Add(self.Root, "Destroy")
end

function VFXHandler.Track(self: VFXHandler, instance: Instance): ()
	if not instance:IsA("BasePart") or self.Targets[instance] or not instance:IsDescendantOf(workspace) then
		return
	end
	local target = Target.new(instance, self.Root, self.Templates)
	self.Targets[instance] = target
	self.Janitor:Add(target, "Destroy", instance)
end

function VFXHandler.Untrack(self: VFXHandler, instance: Instance): ()
	self.Janitor:Remove(instance)
	self.Targets[instance] = nil
end

function VFXHandler.BindCharacter(self: VFXHandler, player: Player, model: Model?): ()
	local previous = self.Characters[player]
	if previous then
		previous:Destroy()
	end
	if model then
		self.Characters[player] = Character.new(model, self.Root, self.Templates)
	else
		self.Characters[player] = nil
	end
end

function VFXHandler.AttachPlayer(self: VFXHandler, player: Player): ()
	local janitor = Janitor.new()
	self.Janitor:Add(janitor, "Destroy", player)
	janitor:Add(
		player.CharacterAdded:Connect(function(model: Model): ()
			self:BindCharacter(player, model)
		end),
		"Disconnect"
	)
	janitor:Add(
		player.CharacterRemoving:Connect(function(): ()
			self:BindCharacter(player, nil)
		end),
		"Disconnect"
	)
	janitor:Add(function(): ()
		self:BindCharacter(player, nil)
	end, true)
	self:BindCharacter(player, player.Character)
end

function VFXHandler.Burst(
	self: VFXHandler,
	name: string,
	instance: Instance?,
	frame: CFrame,
	owner: number,
	time: number
): ()
	local now = workspace:GetServerTimeNow()
	if now - time > Config.MaxEventAge then
		return
	end
	if name == "Sweep" then
		local player = Players:GetPlayerByUserId(owner)
		local character = player and self.Characters[player]
		if character and instance and instance:IsDescendantOf(character.Model) then
			character:AuthorizeSweep(time)
		end
		return
	end
	local template = self.Templates[name]
	if not template or Config.Effects[name] ~= "Burst" then
		return
	end
	local part = if instance and instance:IsA("BasePart") then instance else nil
	local camera = workspace.CurrentCamera
	local position = if part then part.Position else frame.Position
	if not camera or (camera.CFrame.Position - position).Magnitude > Config.Distance then
		return
	end
	if #self.Bursts >= Config.MaxBursts then
		return
	end
	local visual = Effect.new(template, self.Root)
	visual:Burst(now)
	-- Cleaning remains at the cleaned surface; reactions follow the guest's head.
	local follows = if name == "Cleaning" then nil else part
	self.Bursts[#self.Bursts + 1] = {
		Visual = visual,
		Part = follows,
		Guard = part,
		GuardOwner = part and part:GetAttribute("OwnerUserId"),
		Frame = frame,
		Owner = owner,
	}
	self.Janitor:Add(visual, "Destroy", visual)
end

function VFXHandler.Step(self: VFXHandler): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now, position = workspace:GetServerTimeNow(), camera.CFrame.Position
	for part, target in self.Targets do
		if part:IsDescendantOf(workspace) then
			target:Step(now, position)
		else
			self:Untrack(part)
		end
	end
	for player, character in self.Characters do
		character:Step(Tools:GetTool(player), now, position)
	end
	for index = #self.Bursts, 1, -1 do
		local burst = self.Bursts[index]
		local missing = burst.Guard
			and (
				not burst.Guard:IsDescendantOf(workspace)
				or burst.Guard:GetAttribute("OwnerUserId") ~= burst.GuardOwner
			)
		if missing or now >= burst.Visual.ExpiresAt or not Players:GetPlayerByUserId(burst.Owner) then
			self.Janitor:Remove(burst.Visual)
			table.remove(self.Bursts, index)
		else
			burst.Visual:Step(if burst.Part then burst.Part.CFrame else burst.Frame, now)
		end
	end
end

function VFXHandler.OnStart(self: VFXHandler): ()
	local assets = ReplicatedStorage:WaitForChild("Assets", Config.AssetTimeout)
	local folder = assets and assets:WaitForChild("VFX", Config.AssetTimeout)
	if not folder then
		warn("[VFXHandler] Assets.VFX is missing")
		return
	end
	for name in Config.Effects do
		local template = folder:FindFirstChild(name)
		if template and template:IsA("BasePart") then
			self.Templates[name] = template
		else
			warn(`[VFXHandler] Missing template {name}`)
		end
	end
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(function(instance: Instance): ()
			self:Track(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(instance: Instance): ()
			self:Untrack(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Config.Tag) do
		self:Track(instance)
	end
	self.Janitor:Add(
		Players.PlayerAdded:Connect(function(player: Player): ()
			self:AttachPlayer(player)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Players.PlayerRemoving:Connect(function(player: Player): ()
			self.Janitor:Remove(player)
		end),
		"Disconnect"
	)
	for _, player in Players:GetPlayers() do
		self:AttachPlayer(player)
	end
	self.Janitor:Add(
		Bus.VFX.Burst.OnClientEvent:Connect(
			function(name: string, part: Instance?, frame: CFrame, owner: number, time: number): ()
				self:Burst(name, part, frame, owner, time)
			end
		),
		"Disconnect"
	)
	RunService:BindToRenderStep(BIND_NAME, Config.RenderPriority, function(): ()
		self:Step()
	end)
	self.Janitor:Add(function(): ()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end, true)
end

function VFXHandler.Destroy(self: VFXHandler): ()
	self.Janitor:Destroy()
	table.clear(self.Targets)
	table.clear(self.Bursts)
end

export type VFXHandler = typeof(VFXHandler) & {
	Janitor: any,
	Root: Folder,
	Templates: { [string]: BasePart },
	Targets: { [Instance]: Target.Target },
	Characters: { [Player]: Character.Character },
	Bursts: { Burst },
}
return VFXHandler :: VFXHandler
