--!strict
-- One client writer moves each bakery's convoy and cargo from coherent server snapshots.

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ Modules ]]--
local CarryModel = require(ReplicatedStorage.Shared.CarryModel)
local FoodModel = require(ReplicatedStorage.Shared.FoodModel)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Motion = require(ReplicatedStorage.Shared.Configs.RailCartMotion)
local RailPath = require(ReplicatedStorage.Shared.RailPath)

--[[ Types ]]--
type CartSnapshot = { Id: string, Payload: string, Distance: number, Target: number, Delay: number, Speed: number }
type Snapshot = { Time: number, Carts: { CartSnapshot }, Loader: string? }
type Wagon = {
	Cart: FoodModel.FoodModel,
	Cargo: FoodModel.FoodModel?,
	Payload: string,
	Rotation: CFrame?,
	Distance: number,
	Correction: number,
	Janitor: any,
}
type Visual = { Step: (number, number) -> (), Destroy: () -> () }

--[[ Tables ]]--
local RailCartHandler = {}

--[[ Private Functions ]]--
local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Keep the last complete state while a late/older publisher has not supplied all motion fields.
local function readSnapshot(encoded: string): Snapshot?
	local ok, value = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or typeof(value) ~= "table" or not isNumber(value.Time) or typeof(value.Carts) ~= "table" then
		return nil
	end
	if value.Loader ~= nil and typeof(value.Loader) ~= "string" then
		return nil
	end
	local ids = {}
	for _, cart in value.Carts do
		if
			typeof(cart) ~= "table"
			or typeof(cart.Id) ~= "string"
			or typeof(cart.Payload) ~= "string"
			or not isNumber(cart.Distance)
			or not isNumber(cart.Target)
			or not isNumber(cart.Delay)
			or not isNumber(cart.Speed)
			or ids[cart.Id]
		then
			return nil
		end
		ids[cart.Id] = true
	end
	if value.Loader and ids[value.Loader] then
		return nil
	end
	return value
end

local function distance(cart: CartSnapshot, time: number, now: number): number
	local projected = cart.Distance + math.max(0, now - time - cart.Delay) * cart.Speed
	return if cart.Speed < 0
		then math.max(cart.Target, projected)
		elseif cart.Speed > 0 then math.min(cart.Target, projected)
		else cart.Distance
end

local function bindCart(part: BasePart, root: Folder, source: Instance): Visual
	local janitor = Janitor.new()
	local folder = Instance.new("Folder")
	folder.Name = `{part:GetAttribute("OwnerUserId")}_RailCarts`
	folder.Parent = root
	janitor:Add(folder, "Destroy")
	local wagons: { [string]: Wagon } = {}
	local path: RailPath.Path? = nil
	local pathText: string? = nil
	local snapshot: Snapshot? = nil

	local function create(id: string): Wagon?
		local cart = FoodModel.FromSource(source, folder, Motion.CartSize, false)
		if not cart then
			return nil
		end
		local owner = Janitor.new()
		owner:Add(cart, "Destroy")
		janitor:Add(owner, "Destroy", id)
		cart.Model.Name = id
		cart.Model:SetAttribute("CartId", id)
		local wagon: Wagon =
			{ Cart = cart, Cargo = nil, Payload = "", Rotation = nil, Distance = 0, Correction = 0, Janitor = owner }
		wagons[id] = wagon
		return wagon
	end

	local function place(wagon: Wagon, travel: number, deltaTime: number): ()
		local currentPath = path
		if not currentPath then
			return
		end
		local frame = RailPath.Sample(currentPath, travel)
		local rotation = wagon.Rotation
		wagon.Rotation = if rotation
			then rotation:Lerp(frame.Rotation, 1 - math.exp(-Motion.TurnSpeed * deltaTime))
			else frame.Rotation
		frame = CFrame.new(frame.Position) * (wagon.Rotation :: CFrame)
		wagon.Cart:SetCFrame(frame)
		if wagon.Cargo then
			wagon.Cargo:SetCFrame(frame * CFrame.new(0, wagon.Cart.Size.Y * Motion.CargoHeight, 0))
		end
		wagon.Distance = travel
	end

	local function step(deltaTime: number, now: number): ()
		local current = snapshot
		if not path or not current then
			return
		end
		local previous: number? = nil
		local previousTarget: number? = nil
		for _, entry in current.Carts do
			local wagon = wagons[entry.Id]
			if not wagon then
				continue
			end
			wagon.Correction *= math.exp(-Motion.CorrectionSpeed * deltaTime)
			local travel = math.clamp(distance(entry, current.Time, now) + wagon.Correction, 0, entry.Target)
			if previous and previousTarget then
				travel = math.min(travel, math.max(0, previous - (previousTarget - entry.Target)))
			end
			place(wagon, travel, deltaTime)
			previous, previousTarget = travel, entry.Target
		end
		local loader = current.Loader and wagons[current.Loader]
		if loader then
			place(loader, 0, deltaTime)
		end
	end

	local function refresh(): ()
		local route = part:GetAttribute(Motion.PathAttribute)
		local motion = part:GetAttribute(Motion.MotionAttribute)
		if typeof(route) ~= "string" or typeof(motion) ~= "string" then
			return
		end
		if pathText ~= route then
			local points = {}
			for index, point in HttpService:JSONDecode(route) do
				points[index] = { Position = Vector3.new(point[1], point[2], point[3]), Distance = point[4] }
			end
			if #points < 2 then
				return
			end
			path = { Points = points, Length = points[#points].Distance, Stops = {} }
			pathText = route
		end
		local nextSnapshot = readSnapshot(motion)
		if not nextSnapshot then
			return
		end
		local now = workspace:GetServerTimeNow()
		step(0, now)
		local keep = {}
		for _, entry in nextSnapshot.Carts do
			local previous = wagons[entry.Id]
			local wagon = previous or create(entry.Id)
			if not wagon then
				continue
			end
			keep[entry.Id] = true
			wagon.Correction = if previous then wagon.Distance - distance(entry, nextSnapshot.Time, now) else 0
			if wagon.Payload ~= entry.Payload then
				wagon.Janitor:Remove("Cargo")
				wagon.Payload = entry.Payload
				wagon.Cargo = if entry.Payload ~= ""
					then CarryModel.new({ Kind = "Ingredient", Id = entry.Payload }, folder)
					else nil
				if wagon.Cargo then
					wagon.Cargo.Model:SetAttribute("CartId", entry.Id)
					wagon.Janitor:Add(wagon.Cargo, "Destroy", "Cargo")
				end
			end
		end
		local loader = nextSnapshot.Loader
		if loader then
			keep[loader] = true
			local wagon = wagons[loader] or create(loader)
			if wagon then
				wagon.Janitor:Remove("Cargo")
				wagon.Cargo, wagon.Payload, wagon.Correction = nil, "", 0
			end
		end
		for id in wagons do
			if keep[id] then
				continue
			end
			janitor:Remove(id)
			wagons[id] = nil
		end
		snapshot = nextSnapshot
		step(0, now)
	end

	janitor:Add(part:GetAttributeChangedSignal(Motion.PathAttribute):Connect(refresh), "Disconnect")
	janitor:Add(part:GetAttributeChangedSignal(Motion.MotionAttribute):Connect(refresh), "Disconnect")
	refresh()
	return {
		Step = step,
		Destroy = function(): ()
			janitor:Destroy()
		end,
	}
end

--[[ Handling ]]--
function RailCartHandler.OnInit(self: RailCartHandler): ()
	self.Janitor = Janitor.new()
	self.Carts = {}
end

function RailCartHandler.OnStart(self: RailCartHandler): ()
	local garden = ReplicatedStorage.Assets.Models:WaitForChild("GardenCare", 10)
	local source = garden and garden:WaitForChild("Cart", 10)
	if not source then
		warn("[RailCartHandler] Assets.Models.GardenCare.Cart is missing")
		return
	end
	self.Source = source
	local root = Instance.new("Folder")
	root.Name = "RailCartVisuals"
	root.Parent = workspace
	self.Root = root
	self.Janitor:Add(root, "Destroy")
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(Motion.Tag):Connect(function(instance: Instance): ()
			self:Track(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Motion.Tag):Connect(function(instance: Instance): ()
			self:Untrack(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Motion.Tag) do
		self:Track(instance)
	end
	self.Janitor:Add(
		RunService.PreRender:Connect(function(deltaTime: number): ()
			local now = workspace:GetServerTimeNow()
			for _, visual in self.Carts do
				visual.Step(deltaTime, now)
			end
		end),
		"Disconnect"
	)
end

function RailCartHandler.Track(self: RailCartHandler, instance: Instance): ()
	if not instance:IsA("BasePart") or self.Carts[instance] then
		return
	end
	local visual = bindCart(instance, self.Root, self.Source)
	self.Carts[instance] = visual
	self.Janitor:Add(visual, "Destroy", instance)
end

function RailCartHandler.Untrack(self: RailCartHandler, instance: Instance): ()
	self.Janitor:Remove(instance)
	self.Carts[instance] = nil
end

function RailCartHandler.Destroy(self: RailCartHandler): ()
	self.Janitor:Destroy()
	table.clear(self.Carts)
end

export type RailCartHandler = typeof(RailCartHandler) & {
	Janitor: any,
	Root: Folder,
	Source: Instance,
	Carts: { [Instance]: Visual },
}

return RailCartHandler :: RailCartHandler
