--!strict
-- Floating status lines over the local player's busy stations: "Mixing 5s", "Baking 12s",
-- "Needs firewood". A station view marks such a state with `Status` (Shared/BuildingViews); the
-- prompt plate only keeps that line on the station last used, so every other busy station would
-- otherwise say nothing. One outlined label per station, hidden while that station's own prompt
-- plate is showing the same line or a page covers the world. Presentation only: the text comes
-- from the same view the prompts use.
--
-- An alert ("Needs firewood") is not written: a round icon with the firewood model sits in the
-- oven's firebox, where the log goes, and stays up while the player stands at the oven.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local BuildingsConfig = require(_Shared.Configs.Buildings)
local Config = require(_Shared.Configs.StationStatus)
local DataClient = require(_Handlers.DataHandlerClient)
local FoodPreview = require(_Shared.UI.FoodPreview)
local GameTypes = require(_Shared.GameTypes)
local Interact = require(_Handlers.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local OvenFuel = require(_Shared.Configs.OvenFuel)
local Pages = require(_Shared.UI.Stores.Pages)
local PromptHandler = require(_Handlers.PromptHandler)
local Theme = require(_Shared.UI.Theme)
local World = require(_Shared.World)

--[[ Types ]]--
type LineTag = { Billboard: BillboardGui, Line: TextLabel }
type IconTag = { Billboard: BillboardGui, Icon: ImageLabel, Pulse: UIScale }

--[[ Constants ]]--
local ICON = Config.AlertIcon
-- The log the icon shows: the same item the player carries to the oven.
local FUEL_ITEM: GameTypes.ItemStack = { Kind = "Fuel", Id = BuildingsConfig.FuelItemId }
local HORIZONTAL = Vector3.new(1, 0, 1)

--[[ Tables ]]--
local StationStatusHandler = {
	-- UIHandler hands FoodPreview its viewport template.
	dependencies = { "DataClient", "InteractHandler", "PromptHandler", "UIHandler" },
}

--[[ Private Functions ]]--
-- A hidden, depth-tested billboard under PlayerGui. Depth testing lets other rooms' walls cover it;
-- AlwaysOnTop would also stop the icon's viewport from drawing.
local function newBillboard(name: string, adornee: BasePart, width: number, height: number): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(width, height)
	billboard.MaxDistance = Config.MaxDistance
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.AlwaysOnTop = false
	billboard.Enabled = false
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return billboard
end

local function round(gui: GuiObject): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = gui
end

-- Horizontal offset of `distance` studs from `position` toward the camera at `eye`.
local function towardCamera(eye: Vector3, position: Vector3, distance: number): Vector3
	local toCamera = (eye - position) * HORIZONTAL
	return if toCamera.Magnitude > 0 then toCamera.Unit * distance else Vector3.zero
end

local function buildLine(part: BasePart): LineTag
	local billboard = newBillboard("StationStatus", part, Config.Width, Config.Height)

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

	return { Billboard = billboard, Line = text }
end

-- The fire part OvenView put in this station's firebox, in the same bakery.
local function findFirebox(part: BasePart): BasePart?
	local propId = part:GetAttribute(BuildingsConfig.IdAttribute)
	local bakeries = World.Bakeries()
	if typeof(propId) ~= "string" or not bakeries then
		return nil
	end
	local bakery: Instance? = part
	while bakery and bakery.Parent ~= bakeries do
		bakery = bakery.Parent
	end
	local fire = bakery and bakery:FindFirstChild(OvenFuel.FirePartPrefix .. propId)
	return if fire and fire:IsA("BasePart") then fire else nil
end

local function buildIcon(fire: BasePart): IconTag
	local billboard = newBillboard("StationAlert", fire, ICON.Size, ICON.Size)

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.new(1, -ICON.EdgeThickness * 2, 1, -ICON.EdgeThickness * 2)
	plate.BackgroundColor3 = ICON.Plate
	plate.Parent = billboard
	round(plate)
	local edge = Instance.new("UIStroke")
	edge.Color = ICON.Edge
	edge.Thickness = ICON.EdgeThickness
	edge.Parent = plate
	local pulse = Instance.new("UIScale")
	pulse.Parent = plate

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(ICON.ItemScale, ICON.ItemScale)
	icon.BackgroundTransparency = 1
	icon.Parent = plate
	FoodPreview.ShowItem(icon, FUEL_ITEM)

	-- Above the plate and the firewood model.
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(ICON.BadgeAt.X, ICON.BadgeAt.Y)
	badge.Size = UDim2.fromOffset(ICON.BadgeSize, ICON.BadgeSize)
	badge.BackgroundColor3 = ICON.Badge
	badge.Text = "!"
	badge.TextColor3 = ICON.BadgeText
	badge.FontFace = Theme.Fonts.ExtraBold
	badge.TextScaled = true
	badge.ZIndex = icon.ZIndex + 2
	badge.Parent = plate
	round(badge)

	return { Billboard = billboard, Icon = icon, Pulse = pulse }
end

--[[ Handling ]]--
function StationStatusHandler.OnStart(self: StationStatusHandler): ()
	self.Janitor = Janitor.new()
	self.Tags = {}
	self.Icons = {}
	self.Accumulator = 0
	self.Janitor:Add(function(): ()
		for part in self.Tags do
			self:Remove(part)
		end
		for part in self.Icons do
			self:RemoveIcon(part)
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
-- the part sits in; following the camera per frame keeps the label steady while it orbits. Icons
-- sit in front of their firebox and breathe.
function StationStatusHandler.Place(self: StationStatusHandler): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	for part, tag in self.Tags do
		if tag.Billboard.Enabled then
			local lift = Vector3.new(0, part.Size.Y / 2 + Config.Lift, 0)
			tag.Billboard.StudsOffsetWorldSpace = lift + towardCamera(eye, part.Position, Config.Forward)
		end
	end

	local breath = (math.sin(os.clock() * math.pi * 2 / ICON.PulseSeconds) + 1) / 2
	for _, alert in self.Icons do
		local fire = alert.Billboard.Adornee
		if alert.Billboard.Enabled and fire and fire:IsA("BasePart") then
			alert.Billboard.StudsOffsetWorldSpace = towardCamera(eye, fire.Position, ICON.Forward)
			alert.Pulse.Scale = 1 + ICON.PulseScale * breath
		end
	end
end

function StationStatusHandler.Refresh(self: StationStatusHandler): ()
	local covered = Pages.Current:peek() ~= Pages.Names.None or Pages.Presenting:peek()
	local prompt, billboard = PromptHandler:GetActiveView()
	-- The station whose prompt plate is up already shows its status line there.
	local plated = if prompt and billboard and billboard.Enabled then prompt.Parent else nil
	local lines: { [BasePart]: boolean } = {}
	local icons: { [BasePart]: boolean } = {}

	for _, part in Interact:GetParts() do
		local state = Interact:Describe(part)
		if state.Status ~= true or state.Action ~= nil then
			continue
		end
		local alert = state.Alert == true
		local fire = if alert then findFirebox(part) else nil
		if fire then
			-- The icon replaces the words, even beside the station's own prompt (which hides them).
			icons[part] = true
			self:ShowIcon(part, fire, not covered)
		else
			lines[part] = true
			self:ShowLine(part, state.Label, alert, not covered and plated ~= part)
		end
	end

	for part in self.Tags do
		if not lines[part] then
			self:Remove(part)
		end
	end
	for part in self.Icons do
		if not icons[part] then
			self:RemoveIcon(part)
		end
	end
end

function StationStatusHandler.ShowLine(
	self: StationStatusHandler,
	part: BasePart,
	text: string,
	alert: boolean,
	visible: boolean
): ()
	local tag = self.Tags[part]
	if not tag then
		tag = buildLine(part)
		self.Tags[part] = tag
	end
	tag.Line.Text = text
	tag.Line.TextColor3 = if alert then Config.Alert else Config.Face
	tag.Billboard.Enabled = visible
end

-- A rebuilt oven brings a new fire part, so an icon on the old one is replaced.
function StationStatusHandler.ShowIcon(self: StationStatusHandler, part: BasePart, fire: BasePart, visible: boolean): ()
	local alert = self.Icons[part]
	if alert and alert.Billboard.Adornee == fire then
		alert.Billboard.Enabled = visible
		return
	end
	self:RemoveIcon(part)
	local built = buildIcon(fire)
	built.Billboard.Enabled = visible
	self.Icons[part] = built
end

function StationStatusHandler.Remove(self: StationStatusHandler, part: BasePart): ()
	local tag = self.Tags[part]
	if tag then
		tag.Billboard:Destroy()
		self.Tags[part] = nil
	end
end

function StationStatusHandler.RemoveIcon(self: StationStatusHandler, part: BasePart): ()
	local alert = self.Icons[part]
	if alert then
		FoodPreview.Clear(alert.Icon)
		alert.Billboard:Destroy()
		self.Icons[part] = nil
	end
end

function StationStatusHandler.Destroy(self: StationStatusHandler): ()
	self.Janitor:Destroy()
end

export type StationStatusHandler = typeof(StationStatusHandler) & {
	Janitor: any,
	Tags: { [BasePart]: LineTag },
	Icons: { [BasePart]: IconTag },
	Accumulator: number,
}

return StationStatusHandler :: StationStatusHandler
