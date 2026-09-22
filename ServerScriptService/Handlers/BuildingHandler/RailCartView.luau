--!strict
-- Publish the complete convoy coherently. Clients alone render carts and cargo.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

--[[ Modules ]]--
local Data = require(ServerScriptService.Handlers.DataHandler)
local Garden = require(ReplicatedStorage.Shared.Configs.Garden)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Motion = require(ReplicatedStorage.Shared.Configs.RailCartMotion)
local RailPath = require(ReplicatedStorage.Shared.RailPath)

--[[ Tables ]]--
local RailCartView = {}
RailCartView.__index = RailCartView

export type RailCartView = typeof(setmetatable(
	{} :: {
		Building: any,
		MotionKey: string?,
		Frames: { CFrame },
		Janitor: any,
	},
	RailCartView
))

--[[ Handling ]]--
function RailCartView.new(_root: Instance, building: any): RailCartView?
	if not building.State or not building.RailPath then
		return nil
	end
	local self = setmetatable({ Building = building, Frames = {}, Janitor = Janitor.new() }, RailCartView)
	local points = {}
	for _, point in building.RailPath.Points do
		local position = point.Position
		points[#points + 1] = { position.X, position.Y, position.Z, point.Distance }
	end
	for index, distance in building.RailPath.Stops do
		self.Frames[index] = RailPath.Sample(building.RailPath, distance)
	end
	building.Part:SetAttribute(Motion.PathAttribute, HttpService:JSONEncode(points))
	self.Janitor:Add(function(): ()
		building.Part:RemoveTag(Motion.Tag)
		building.Part:SetAttribute(Motion.PathAttribute, nil)
		building.Part:SetAttribute(Motion.MotionAttribute, nil)
	end, true)
	self:Update(0, workspace:GetServerTimeNow())
	building.Part:AddTag(Motion.Tag)
	return self
end

function RailCartView.Update(self: RailCartView, _deltaTime: number, now: number): ()
	local building = self.Building
	local state = building.State
	local data = Data:GetData(building.Player)
	local paused = not data or data.Session.Day.Phase == "Summary"
	local ready = state.SpawnRemaining <= 0 and #state.Queue < Garden.CartCapacity
	local keys = { tostring(paused), tostring(ready), tostring(state.NextId) }
	local carts = {}
	for index = 1, #state.Carts do
		local cart = state.Carts[index]
		keys[#keys + 1] = `{cart.Id}:{state.Queue[index]}:{cart.Delay > 0}:{cart.Arrived}:{cart.Speed}`
		carts[index] = {
			Id = cart.Id,
			Payload = state.Queue[index],
			Distance = cart.Distance,
			Target = building.RailPath.Stops[index],
			Delay = cart.Delay,
			Speed = if paused or cart.Arrived then 0 else cart.Speed,
		}
	end
	local key = table.concat(keys, ":")
	if self.MotionKey == key then
		return
	end
	building.Part:SetAttribute(
		Motion.MotionAttribute,
		HttpService:JSONEncode({
			Time = now,
			Carts = carts,
			Loader = if ready then `cart_{state.NextId + 1}` else nil,
		})
	)
	self.MotionKey = key
end

function RailCartView.GetPickupOrigin(self: RailCartView, index: number): Vector3?
	local frame = self.Frames[index]
	return if frame then frame.Position + Vector3.new(0, Motion.CartSize.Y * Motion.CargoHeight + 0.5, 0) else nil
end

function RailCartView.Destroy(self: RailCartView): ()
	self.Janitor:Destroy()
end

return RailCartView
