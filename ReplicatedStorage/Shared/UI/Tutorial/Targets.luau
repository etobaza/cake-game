--!strict
-- Resolves only the local bakery and authored UI. Hidden/clipped GUI never becomes a spotlight hole.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Base = require(ReplicatedStorage.Shared.Configs.Base)
local Buildings = require(ReplicatedStorage.Shared.Configs.Buildings)
local Garden = require(ReplicatedStorage.Shared.Configs.Garden)
local Geometry = require(script.Parent.Geometry)
local Interact = require(ReplicatedStorage.Handlers.InteractHandler)
local Types = require(ReplicatedStorage.Shared.GameTypes)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)

--[[ Tables ]]--
local Targets = {}
local OvenPaths = {
	{ "1ndFloor", "Kitchen", "Decoration", "Oven" },
	{ "1ndFloor", "Kitchen", "Upgrades", " OvenUpgrade", "Upgrade2", "Oven" },
	{ "1ndFloor", "Kitchen", "Upgrades", " OvenUpgrade", "Upgrade1", "Oven" },
}

export type Target = {
	gui: GuiObject?,
	part: BasePart?,
	model: Instance?,
	frame: CFrame?,
	size: Vector3?,
	message: string?,
}

--[[ Private Functions ]]--
local function bakeryOf(part: Instance): Instance?
	local root = part
	while root.Parent and root.Parent.Name ~= Base.BakeriesFolderName do
		root = root.Parent
	end
	return if root.Parent then root else nil
end

local function ui(path: string): GuiObject?
	local names = string.split(path, ".")
	local screen = if names[1] == "UI" then UIHandler.Hud else UIHandler:GetPanel(names[1])
	local current: Instance? = screen
	for index = 2, #names do
		current = current and current:FindFirstChild(names[index])
	end
	if not current and screen and names[#names] == "Exit" then
		current = screen:FindFirstChild("Exit", true) or screen:FindFirstChild("CloseButton", true)
	end
	return if current and current:IsA("GuiObject") then current else nil
end

local function seat(part: BasePart, index: number): (CFrame?, Vector3?)
	local bakeries = workspace:FindFirstChild(Base.BakeriesFolderName)
	local reference = bakeries and bakeries:FindFirstChild(Base.TemplateName)
	local anchors = reference and reference:FindFirstChild(Base.AnchorsFolderName)
	local anchor = anchors and anchors:FindFirstChild(part:GetAttribute(Buildings.IdAttribute))
	if not anchor or not anchor:IsA("BasePart") then
		return nil, nil
	end
	local attachment = anchor:FindFirstChild(if index == 1 then "FoodSurface" else "FoodSurface" .. index)
	if not attachment or not attachment:IsA("Attachment") then
		return nil, nil
	end
	local transform = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0) * anchor.CFrame:Inverse()
	return transform * attachment.WorldCFrame * CFrame.new(0, 0.5, 0), Vector3.new(2.5, 1.5, 2.5)
end

local function displaySurface(part: BasePart, bakery: Instance): CFrame?
	local bakeries = bakery.Parent
	local reference = bakeries and bakeries:FindFirstChild(Base.TemplateName)
	local anchors = reference and reference:FindFirstChild(Base.AnchorsFolderName)
	local origin = Buildings.ResolvePath(bakery, Base.OriginPath)
	local referenceOrigin = reference and Buildings.ResolvePath(reference, Base.OriginPath)
	if
		not anchors
		or not origin
		or not origin:IsA("BasePart")
		or not referenceOrigin
		or not referenceOrigin:IsA("BasePart")
	then
		return nil
	end
	local transform = origin.CFrame * referenceOrigin.CFrame:Inverse()
	local point = part.Position - Vector3.yAxis * part.Size.Y / 2
	for _, anchor in anchors:GetChildren() do
		if not anchor:IsA("BasePart") or not anchor.Name:match("^display_%d+$") then
			continue
		end
		if ((transform * anchor.CFrame).Position - point).Magnitude > 0.1 then
			continue
		end
		local surface = anchor:FindFirstChild("FoodSurface")
		if surface and surface:IsA("Attachment") then
			return transform * surface.WorldCFrame
		end
	end
	return nil
end

local function world(id: string, seatIndex: number?): Target?
	local part = Interact:GetProp(id)
	if not part then
		return nil
	end
	local bakery = bakeryOf(part)
	local model = Buildings.WorldModel(part) or part:FindFirstChildWhichIsA("Model")
	local oven = id:match("^oven_(%d+)$")
	local ovenPath = if oven then OvenPaths[tonumber(oven) :: number] else nil
	if ovenPath and bakery then
		model = Buildings.ResolvePath(bakery, ovenPath)
	end
	if id == "freezer_1" and bakery then
		model = Buildings.ResolvePath(bakery, { "1ndFloor", "Kitchen", "Upgrades", "Freezer", "Upgrade" })
	end
	if id == "coffee_1" and bakery then
		model = Buildings.ResolvePath(bakery, { "1ndFloor", "Cafe", "Upgrades", "CoffeeMachine", "Upgrade" })
	end
	if id == "fuel" and bakery then
		model = Buildings.ResolvePath(bakery, { "1ndFloor", "Kitchen", "Upgrades", "FireWood", "Upgrade", "FireWood" })
	end
	if id:match("^display_%d+$") and bakery then
		local food = bakery:FindFirstChild("Food_" .. id, true)
		local dish = food and food:FindFirstChildWhichIsA("Model")
		if dish then
			return { part = part, model = dish } :: Target
		end
		local surface = displaySurface(part, bakery)
		if surface then
			return { part = part, frame = surface * CFrame.new(0, 0.5, 0), size = Vector3.new(2.8, 1, 2.8) }
		end
	end
	local source = Garden.Sources[id]
	if source and bakery then
		model = bakery:FindFirstChild(source.Folder, true)
	end
	if seatIndex then
		local frame, size = seat(part, seatIndex)
		local food = bakery and bakery:FindFirstChild("Food_" .. id, true)
		for _, child in (if food then food:GetChildren() else {}) :: { Instance } do
			if child:GetAttribute("SeatIndex") ~= seatIndex or not child:IsA("Model") then
				continue
			end
			model = child
			frame, size = nil, nil
			break
		end
		return { part = part, model = model, frame = frame, size = size } :: Target
	end
	return { part = part, model = model or part } :: Target
end

--[[ Handling ]]--
function Targets.Resolve(spec: Types.TutorialTarget?, viewport: Vector2): Target?
	if not spec then
		return nil
	end
	if spec.kind == "World" then
		return world(spec.id, spec.seat)
	end
	if spec.kind == "Gui" then
		local element = ui(spec.id)
		return if element and Geometry.Gui(element, viewport) then { gui = element } else nil
	end
	if spec.kind == "Recipe" then
		local control = spec.control or "Start"
		local button = ui(`RecipeToCook.MainFrame.Container.Content.{spec.id}.Status.{control}`)
		if button and Geometry.Gui(button, viewport) then
			return { gui = button }
		end
		local content = ui("RecipeToCook.MainFrame.Container.Content")
		local message = if control == "InProgress"
			then "Scroll to the recipe's In-Progress button"
			else "Scroll to the recipe's Start button"
		return if content and Geometry.Gui(content, viewport) then { gui = content, message = message } else nil
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local root = if spec.kind == "Order" then UIHandler:GetHud("Order") else playerGui:FindFirstChild("MixerBillboard")
	for _, child in if root then root:GetDescendants() else {} do
		if not child:IsA("GuiObject") then
			continue
		end
		local attribute = if spec.kind == "Order" then "CustomerId" else "IngredientId"
		if child:GetAttribute(attribute) == spec.id and Geometry.Gui(child, viewport) then
			return { gui = child }
		end
	end
	local fallback = if spec.kind == "Ingredient" then world("mixer_1", nil) else nil
	if fallback then
		fallback.message = "Walk closer to the mixer"
	end
	return fallback
end

return Targets
