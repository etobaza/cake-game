-- Guests as physical figures: they walk in through the door wearing a real avatar, take a chair or
-- step up to the display, react to their order, eat and walk back out.
-- The simulation stays entirely in CustomerHandler; this handler only mirrors it into the world,
-- which is why it subscribes to signals instead of deciding anything itself.

--[[ Services ]]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ServerScriptService.Handlers

--[[ Modules ]]--
local Appearance = require(script.Appearance)
local BaseHandler = require(_Handlers.BaseHandler)
local Bus = require(_Shared.Bus)
local CatHandler = require(_Handlers.CatHandler)
local CarpetRoute = require(script.CarpetRoute)
local CustomerHandler = require(_Handlers.CustomerHandler)
local CustomerTypes = require(_Configs.Registries.CustomerTypes)
local DataHandler = require(_Handlers.DataHandler)
local DayCycleHandler = require(_Handlers.DayCycleHandler)
local Guest = require(script.Guest)
local GuestsConfig = require(_Configs.Guests)
local Spots = require(script.Spots)
local Street = require(script.Street)
local TickHandler = require(_Handlers.TickHandler)
local VFX = require(_Configs.VFX)

--[[ Tables ]]--
local CustomerViewHandler = {
	dependencies = {
		"DataHandler",
		"DayCycleHandler",
		"BaseHandler",
		"BuildingHandler",
		"CollisionHandler",
		"CustomerHandler",
		"DisplayHandler",
		"TickHandler",
	},
	-- After CustomerHandler, so the data node of a new guest already exists when the body is built.
	priority = 20,
}

--[[ Private Functions ]]--
local function GetCustomer(player: Player, customerId: string): any?
	local data = DataHandler:GetData(player)

	return data and data.Session.Customers[customerId]
end

local function SitAt(player: Player, customerId: string, guest: Guest.Guest, seat: Seat): ()
	guest:SitOn(seat, function()
		CustomerHandler:ArriveAtSeat(player, customerId)
	end, function()
		CustomerHandler:AbortArrival(player, customerId)
	end)
end

--[[ Handling ]]--
function CustomerViewHandler.OnInit(self: CustomerViewHandler): ()
	self.Bodies = {}
	self.Faces = {}
	self.Folders = {}
	self.Accumulator = 0
end

function CustomerViewHandler.OnStart(self: CustomerViewHandler): ()
	BaseHandler.BaseReady:Connect(function(player: Player, root: Folder)
		self:OpenBase(player, root)
	end)

	BaseHandler.BaseRemoving:Connect(function(player: Player)
		self:CloseBase(player)
	end)

	-- BaseHandler starts earlier and may have fired BaseReady before this observer subscribed.
	-- Catching up here gives every claimed bakery its guest folder in both boot orders.
	for _, player in Players:GetPlayers() do
		local root = BaseHandler:GetBase(player)
		if root then
			self:OpenBase(player, root)
		end
	end

	CustomerHandler.CustomerSpawned:Connect(function(player: Player, customerId: string)
		self:Arrive(player, customerId)
	end)

	CustomerHandler.CustomerSeated:Connect(function(player: Player, customerId: string, tableId: string)
		self:Seat(player, customerId, tableId)
	end)

	CustomerHandler.CustomerEating:Connect(
		function(player: Player, customerId: string, recipeId: string, reaction: string)
			self:Eat(player, customerId, recipeId, reaction)
		end
	)

	CustomerHandler.CustomerLeft:Connect(function(player: Player, customerId: string)
		self:Leave(player, customerId)
	end)
	CustomerHandler.CustomerShopping:Connect(function(player: Player, customerId: string)
		local guest = self:GetGuest(player, customerId)
		if guest then
			self:Route(player, customerId, guest)
		end
	end)
	CustomerHandler.CustomerPurchased:Connect(function(player: Player, customerId: string)
		local guest = self:GetGuest(player, customerId)
		if guest then
			guest:CarryTakeaway()
		end
	end)

	CustomerHandler.CustomerAdopted:Connect(function(player: Player, customerId: string)
		local guest = self:GetGuest(player, customerId)
		if guest then
			guest:CarryCat()
		end
	end)

	-- The friend list is a web call, so it is read once on join and not on the first guest.
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(Appearance.Load, player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(Appearance.Load, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		self:CloseBase(player)
		Appearance.Forget(player)
	end)

	TickHandler.Tick:Connect(function(deltaTime: number)
		self:Refresh(deltaTime)
	end)
end

function CustomerViewHandler.OpenBase(self: CustomerViewHandler, player: Player, root: Folder): ()
	self:CloseBase(player)

	local folder = Instance.new("Folder")
	folder.Name = GuestsConfig.FolderName
	folder.Parent = root

	self.Folders[player] = folder
	self.Bodies[player] = {}
	self.Faces[player] = {}
	local door = Spots.Door(player)
	if door then
		Street.Open(player, folder, door, Spots.Outside(door))
	end
end

function CustomerViewHandler.CloseBase(self: CustomerViewHandler, player: Player): ()
	Street.Close(player)
	for _, guest in (self.Bodies[player] or {}) :: { [string]: Guest.Guest } do
		guest:Destroy()
	end
	local folder = self.Folders[player]
	if folder then
		folder:Destroy()
	end

	self.Folders[player] = nil
	self.Bodies[player] = nil
	self.Faces[player] = nil
end

-- Adopt the reserved pedestrian without replacing or repositioning their existing body.
function CustomerViewHandler.Arrive(self: CustomerViewHandler, player: Player, customerId: string): ()
	local pedestrian = Street.Claim(player, customerId)
	if not pedestrian then
		return
	end
	local guest = pedestrian.Guest
	local customer = GetCustomer(player, customerId)
	local entry = customer and CustomerTypes:Get(customer.TypeId)
	local bodies = self.Bodies[player]
	if not entry or not bodies or guest.Destroyed then
		guest:Destroy()
		return
	end
	guest.Model.Name = customerId
	guest.Model.Parent = self.Folders[player]
	guest.Humanoid.DisplayName = if pedestrian.Identity.Name ~= "" then pedestrian.Identity.Name else entry.name
	bodies[customerId] = guest
	guest.OnBlocked = function()
		local current = GetCustomer(player, customerId)
		if current then
			CustomerHandler:FinishCustomer(player, customerId, current, false)
		end
	end
	self.Faces[player][customerId] = pedestrian.Identity
	DayCycleHandler:TrackGuestBody(player, guest.Model)
	local head = guest.Model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head:SetAttribute(VFX.RoleAttribute, "Guest")
		head:AddTag(VFX.Tag)
	end
	Street.Enter(player, guest, function()
		if self:GetGuest(player, customerId) == guest and GetCustomer(player, customerId) then
			self:Route(player, customerId, guest)
		end
	end)
end

-- Sends the guest to where they belong right now, always through the doorway.
function CustomerViewHandler.Route(
	self: CustomerViewHandler,
	player: Player,
	customerId: string,
	guest: Guest.Guest
): ()
	local door = Spots.Door(player)
	local customer = GetCustomer(player, customerId)
	local bodies = self.Bodies[player]
	if not door or not customer or not bodies then
		return
	end

	if customer.State == "Adopting" and customer.CatId then
		local cat = CatHandler:GetReserved(player, customer.CatId, customerId)
		if not cat then
			return
		end
		guest:WalkRoute(
			CarpetRoute.Build(BaseHandler:GetBase(player), guest.Root.Position, cat.Approach),
			cat.Part.Position,
			function()
				CustomerHandler:ArriveAtCat(player, customerId, guest.Root.Position)
				if CatHandler:GetReserved(player, customer.CatId, customerId) then
					guest:PetCat()
				end
			end
		)
		return
	end
	local spot = Spots.Resolve(player, customer, door)
	local seat = spot.Seat
	local onArrive = if seat
		then function()
			SitAt(player, customerId, guest, seat)
		end
		elseif customer.Kind == "Display" then function()
			CustomerHandler:ArriveAtDisplay(player, customerId)
		end
		else nil

	local points: { Vector3 } = {}
	if customer.State == "Queued" then
		table.insert(points, spot.Target)
	else
		local start = guest.Root.Position
		if door.CFrame:PointToObjectSpace(start).Z < 0 then
			start = Spots.Inside(door)
			table.insert(points, start)
		end
		for _, point in CarpetRoute.Build(BaseHandler:GetBase(player), start, spot.Approach or spot.Target) do
			table.insert(points, point)
		end
		if spot.Approach then
			table.insert(points, spot.Target)
		end
	end
	guest:WalkRoute(points, spot.LookAt, onArrive)
end

function CustomerViewHandler.Seat(self: CustomerViewHandler, player: Player, customerId: string, _tableId: string): ()
	local guest = self:GetGuest(player, customerId)
	if guest and guest.Model:GetAttribute("VisitorState") ~= "Entering" then
		self:Route(player, customerId, guest)
	end
end

function CustomerViewHandler.Eat(
	self: CustomerViewHandler,
	player: Player,
	customerId: string,
	_recipeId: string,
	reaction: string
): ()
	local guest = self:GetGuest(player, customerId)
	if not guest then
		return
	end

	local head = guest.Model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head:SetAttribute(VFX.ChoosingAttribute, false)
		Bus.VFX.Burst:Fire(reaction, head, head.CFrame, player.UserId, workspace:GetServerTimeNow())
	end
end

function CustomerViewHandler.Leave(self: CustomerViewHandler, player: Player, customerId: string): ()
	local guest = self:GetGuest(player, customerId)
	Street.Cancel(player, customerId)
	local bodies = self.Bodies[player]
	local faces = self.Faces[player]
	local door = Spots.Door(player)
	if not guest or not bodies then
		return
	end

	bodies[customerId] = nil
	local head = guest.Model:FindFirstChild("Head")
	if head then
		head:SetAttribute(VFX.ChoosingAttribute, false)
	end

	if faces and faces[customerId] then
		faces[customerId] = nil
	end

	if not door then
		guest:Destroy()
		return
	end

	-- A queued guest is already outside; leaving must not send them through the dining room.
	local start = guest.Root.Position
	local points: { Vector3 } = {}
	local outside = #points == 0 and door.CFrame:PointToObjectSpace(start).Z < 0
	if not outside then
		for _, point in CarpetRoute.Build(BaseHandler:GetBase(player), start, Spots.Inside(door)) do
			table.insert(points, point)
		end
	end
	table.insert(points, Spots.Outside(door))
	Street.Exit(player, guest, points, function()
		DayCycleHandler:UntrackGuestBody(player, guest.Model)
		if head then
			head:SetAttribute(VFX.RoleAttribute, nil)
			head:RemoveTag(VFX.Tag)
		end
	end)
end

function CustomerViewHandler.GetGuest(self: CustomerViewHandler, player: Player, customerId: string): Guest.Guest?
	local bodies = self.Bodies[player]

	return bodies and bodies[customerId]
end

-- The shared tick mirrors Choosing into the replicated VFX state.
function CustomerViewHandler.Refresh(self: CustomerViewHandler, deltaTime: number): ()
	self.Accumulator += deltaTime
	if self.Accumulator < GuestsConfig.RefreshInterval then
		return
	end

	self.Accumulator = 0
	Street.Update()

	for player, bodies in self.Bodies do
		for customerId, guest in bodies do
			self:RefreshGuest(player, customerId, guest)
		end
	end
end

function CustomerViewHandler.RefreshGuest(
	_self: CustomerViewHandler,
	player: Player,
	customerId: string,
	guest: Guest.Guest
): ()
	local customer = GetCustomer(player, customerId)
	if not customer then
		return
	end
	local head = guest.Model:FindFirstChild("Head")
	if head then
		head:SetAttribute(VFX.ChoosingAttribute, customer.State == "Choosing")
	end
end

export type CustomerViewHandler = typeof(CustomerViewHandler) & {
	Bodies: { [Player]: { [string]: Guest.Guest } },
	Faces: { [Player]: { [string]: Appearance.Identity } },
	Folders: { [Player]: Folder },
	Accumulator: number,
}

return CustomerViewHandler :: CustomerViewHandler
