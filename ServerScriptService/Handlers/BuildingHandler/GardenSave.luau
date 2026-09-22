--!strict
-- Pure profile migration/recovery, called by DataHandler before readiness and final saving.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared

--[[ Modules ]]--
local Config = require(_Shared.Configs.Garden)
local Ingredients = require(_Shared.Configs.Registries.Ingredients)

--[[ Tables ]]--
local GardenSave = {}

--[[ Private Functions ]]--
local function add(pantry: any, id: string, amount: number): ()
	if amount > 0 and Ingredients:Get(id) and not Ingredients:IsInfinite(id) then
		pantry[id] = (pantry[id] or 0) + amount
	end
end

--[[ Handling ]]--
function GardenSave.Migrate(data: any): ()
	local cloud = data.Cloud
	local cart = cloud.GardenCart
	if (cart.Version or 0) < 2 then
		-- Preserve both delivered stock and the old shuttle's in-flight ingredient exactly once.
		if cart.Payload and cart.Payload ~= "" then
			cart.Queue[#cart.Queue + 1] = cart.Payload
		end
		cart.Carts = {}
		cart.NextId = 0
		for index = 1, #cart.Queue do
			cart.NextId += 1
			cart.Carts[index] = { Id = `cart_{cart.NextId}`, Distance = 0, Delay = 0, Speed = 0, Arrived = true }
		end
		cart.Day = cloud.Day
		cart.SpawnRemaining = 0
		cart.State, cart.Progress, cart.Payload = nil, nil, nil
		cart.Version = 2
	end
	if cart.Version < 4 then
		-- Preserve version 2 convoys and version 3 cargo. An empty returning shuttle owns no item.
		if cart.Version == 3 and #cart.Queue == 0 then
			cart.Carts = {}
		end
		for index = 1, #cart.Carts do
			cart.Carts[index].Returning = nil
		end
		cart.Version = 4
	end
	if cloud.GardenVersion >= Config.Version then
		return
	end
	local levels = cloud.Base.Upgrades
	local groups: { [string]: { string } } = {
		garden_tree = { "garden_cocoa", "garden_cherry", "garden_apple", "garden_lemon" },
		garden_plot = { "garden_strawberry", "garden_blueberry", "garden_grape", "garden_carrot" },
	}
	for oldId, replacements in groups do
		for index = 1, math.min(levels[oldId] or 0, #replacements) do
			local id = replacements[index]
			levels[id] = math.max(levels[id] or 0, 1)
		end
		levels[oldId] = nil
	end
	for id, source in Config.Sources do
		local group = cloud.Garden[source.Group]
		local old = group[id]
		if not old then
			continue
		end
		local stock = math.max(0, math.floor(old.Stock or 0))
		local remaining = Config.ProduceSeconds
		if (old.ReadyAt or 0) > 0 then
			remaining = math.clamp(old.ReadyAt - workspace:GetServerTimeNow(), 0, Config.ProduceSeconds)
			if remaining == 0 then
				stock += 1
				remaining = Config.ProduceSeconds
			end
		end
		add(cloud.Pantry, source.Produce, math.max(0, stock - Config.Capacity))
		group[id] = {
			Stock = math.min(stock, Config.Capacity),
			GrowRemaining = remaining,
			CareRemaining = if old.Watered then Config.WaterSeconds elseif old.Fed then Config.CleanSeconds else 0,
			CleanDay = 0,
			Day = cloud.Day,
			CareUntil = 0,
			State = "Paused",
		}
	end
	cloud.GardenVersion = Config.Version
end

-- Called without yielding. Clear each recovered source so repeated final-save notifications are safe.
function GardenSave.Recover(data: any): ()
	if not data then
		return
	end
	local hands = data.Session.Hands
	for index = #hands, 1, -1 do
		local item = hands[index]
		if item.Kind == "Ingredient" then
			add(data.Cloud.Pantry, item.Id, 1)
			hands[index] = nil
		end
	end
	for stationId in data.Session.Stations do
		local station = data.Session.Stations[stationId]
		if station.Kind ~= "Mixer" or (station.State ~= "Idle" and station.State ~= "Mixing") then
			continue
		end
		for id, amount in station.Loaded or {} do
			add(data.Cloud.Pantry, id, amount)
		end
		station.Loaded = {}
	end
	for id, source in Config.Sources do
		local state = data.Cloud.Garden[source.Group][id]
		if state then
			state.CareUntil = 0
		end
	end
end

return GardenSave
