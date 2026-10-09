--!strict
-- Floating status lines over the local player's busy stations: "Mixing 5s", "Baking 12s",
-- "Needs firewood". A station view marks such a state with `Status` (Shared/BuildingViews); the
-- prompt plate only keeps that line on the station last used, so every other busy station would
-- otherwise say nothing. One outlined label per station, hidden while that station's own prompt
-- plate is showing the same line or a page covers the world. Presentation only: the text comes
-- from the same view the prompts use.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Config = require(_Shared.Configs.StationStatus)
local DataClient = require(_Handlers.DataHandlerClient)
local Interact = require(_Handlers.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(_Shared.UI.Stores.Pages)
local PromptHandler = require(_Handlers.PromptHandler)
local Theme = require(_Shared.UI.Theme)

--[[ Tables ]]--
local StationStatusHandler = {
	dependencies = { "DataClient", "InteractHandler", "PromptHandler" },
}

--[[ Private Functions ]]--
local function isAlert(text: string): boolean
	local lower = string.lower(text)
	for _, word in Config.AlertWords do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

local function buildTag(part: BasePart): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StationStatus"
	billboard.Adornee = part
	billboard.Size = UDim2.fromOffset(Config.Width, Config.Height)
	billboard.MaxDistance = Config.MaxDistance
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false

	local text = Instance.new("TextLabel")
	text.Name = "Line"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.FontFace = Theme.Fonts.ExtraBold
	text.TextSize = Config.TextSize
	text.TextColor3 = Config.Face
	text.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Ink
	stroke.Thickness = Config.Outline
	stroke.Parent = text

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return billboard, text
end

--[[ Handling ]]--
function StationStatusHandler.OnStart(self: StationStatusHandler): ()
	self.Janitor = Janitor.new()
	self.Tags = {}
	self.Accumulator = 0
	self.Janitor:Add(function(): ()
		for part in self.Tags do
			self:Remove(part)
		end
	end, true)

	DataClient:WaitForData()
	self.Janitor:Add(
		RunService.Heartbeat:Connect(function(deltaTime: number): ()
			self.Accumulator += deltaTime
			if self.Accumulator < Config.RefreshInterval then
				return
			end
			self.Accumulator = 0
			self:Refresh()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		RunService.RenderStepped:Connect(function(): ()
			self:Place()
		end),
		"Disconnect"
	)
end

-- Every frame, lift each label above its part and pull it toward the viewer, out of the model
-- the part sits in; following the camera per frame keeps the label steady while it orbits.
function StationStatusHandler.Place(self: StationStatusHandler): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	for part, tag in self.Tags do
		if not tag.Billboard.Enabled then
			continue
		end
		local toCamera = (eye - part.Position) * Vector3.new(1, 0, 1)
		local forward = if toCamera.Magnitude > 0 then toCamera.Unit * Config.Forward else Vector3.zero
		tag.Billboard.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + Config.Lift, 0) + forward
	end
end

function StationStatusHandler.Remove(self: StationStatusHandler, part: BasePart): ()
	local tag = self.Tags[part]
	if tag then
		tag.Billboard:Destroy()
		self.Tags[part] = nil
	end
end

function StationStatusHandler.Refresh(self: StationStatusHandler): ()
	local covered = Pages.Current:peek() ~= Pages.Names.None
	local prompt, billboard = PromptHandler:GetActiveView()
	-- The station whose prompt plate is up already shows its status line there.
	local plated = if prompt and billboard and billboard.Enabled then prompt.Parent else nil
	local seen: { [BasePart]: boolean } = {}

	for _, part in Interact:GetParts() do
		local state = Interact:Describe(part)
		if state.Status ~= true or state.Action ~= nil then
			continue
		end
		seen[part] = true
		local tag = self.Tags[part]
		if not tag then
			local gui, line = buildTag(part)
			tag = { Billboard = gui, Line = line }
			self.Tags[part] = tag
		end
		tag.Line.Text = state.Label
		tag.Line.TextColor3 = if isAlert(state.Label) then Config.Alert else Config.Face
		tag.Billboard.Enabled = not covered and plated ~= part
	end

	for part in self.Tags do
		if not seen[part] then
			self:Remove(part)
		end
	end
end

function StationStatusHandler.Destroy(self: StationStatusHandler): ()
	self.Janitor:Destroy()
end

export type StationStatusHandler = typeof(StationStatusHandler) & {
	Janitor: any,
	Tags: { [BasePart]: { Billboard: BillboardGui, Line: TextLabel } },
	Accumulator: number,
}

return StationStatusHandler :: StationStatusHandler
