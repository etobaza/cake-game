--!strict
-- Hands out bakeries: one pre-built bakery per player, released on leave.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Libs = _Shared.Libs

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local LoggerUtil = require(_Libs.Logger)
local VacantView = require(script.Parent.BuildingHandler.VacantView)

--[[ Private Variables ]]--
local Logger = LoggerUtil.new({ name = "PlotHandler" })

--[[ Tables ]]--
local PlotHandler = {
	-- The bakery is needed before the base systems bind to it, so this starts before BaseHandler.
	priority = 50,
}

--[[ Handling ]]--
function PlotHandler.OnInit(self: PlotHandler): ()
	self.Folder = workspace:WaitForChild(BaseConfig.BakeriesFolderName) :: Folder
	self.Owners = {}
	self.Assigned = {}
	self.Views = {}
	for _, bakery in self.Folder:GetChildren() do
		if not bakery:IsA("Folder") then
			continue
		end
		local saved = VacantView.Capture(bakery)
		self.Views[bakery] = saved
		VacantView.Apply(saved, false)
	end
end

-- Claims the first free bakery; nil when all of them are taken.
function PlotHandler.Claim(self: PlotHandler, player: Player): Folder?
	local existing = self.Assigned[player]
	if existing then
		return existing
	end

	for _, bakery in self.Folder:GetChildren() do
		if bakery:IsA("Folder") and not self.Owners[bakery] then
			self.Owners[bakery] = player
			self.Assigned[player] = bakery
			VacantView.Apply(self.Views[bakery], true)

			return bakery
		end
	end

	Logger:Warn(`No free bakery for {player.Name}`)

	return nil
end

function PlotHandler.Release(self: PlotHandler, player: Player): ()
	local bakery = self.Assigned[player]
	if not bakery then
		return
	end

	-- BaseHandler releases only after the old owner's deferred cleanup has finished.
	VacantView.Apply(self.Views[bakery], false)
	self.Owners[bakery] = nil
	self.Assigned[player] = nil
end

function PlotHandler.GetPlot(self: PlotHandler, player: Player): Folder?
	return self.Assigned[player]
end

function PlotHandler.GetOwner(self: PlotHandler, bakery: Folder): Player?
	return self.Owners[bakery]
end

export type PlotHandler = typeof(PlotHandler) & {
	Folder: Folder,
	Owners: { [Folder]: Player },
	Assigned: { [Player]: Folder },
	Views: { [Folder]: VacantView.Snapshot },
}

return PlotHandler :: PlotHandler
