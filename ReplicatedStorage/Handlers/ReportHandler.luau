--!strict
-- Drives StarterGui.Report and owns the evening modal across report, menu and upgrades.
-- Counters are read from the server snapshot; opening this page never grants rewards.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Authored = require(_Shared.UI.Authored)
local Config = require(_Shared.Configs.DayReport)
local DataClient = require(_Handlers.DataHandlerClient)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(_Shared.UI.Stores.Pages)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local EVENING_PAGES: { [string]: boolean } = { Report = true, Inventory = true, Upgrades = true }

--[[ Tables ]]--
local ReportHandler = {
	-- Menu must have hydrated its recipe cells before the evening navigation opens it.
	dependencies = { "DataClient", "UIHandler", "MenuHandler" },
}

--[[ Handling ]]--
function ReportHandler.OnStart(self: ReportHandler): ()
	local screen = UIHandler:GetPanel("Report")
	local panel = screen and screen:FindFirstChild("MainFrame")
	local content = panel and Authored.Resolve(panel, { "Middle", "Container", "Content" })
	if not screen or not panel or not content then
		warn("[ReportHandler] StarterGui.Report.MainFrame.Middle.Container.Content is missing")
		return
	end
	self.Janitor = Janitor.new()
	self.Janitor:LinkToInstance(screen)
	self.Panel = panel
	self.Content = content
	self.Modal = false
	DataClient:WaitForData()
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Day", "Phase" }, function(phase: string): ()
			self:RefreshPhase(phase)
		end, "Session"),
		"Disconnect"
	)
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Day", "Summary" }, function(): ()
			self:Refresh()
		end, "Session", true),
		"Disconnect"
	)
	self.Janitor:Add(function(): ()
		if self.Modal then
			Pages.SetLocked(false)
		end
	end, true)
	self:RefreshPhase(DataClient:GetData({ "Day", "Phase" }, "Session"))
end

function ReportHandler.Refresh(self: ReportHandler): ()
	local day = DataClient:GetData({ "Day" }, "Session")
	if not day or day.Phase ~= "Summary" then
		return
	end
	for _, row in Config.Rows do
		local item = self.Content:FindFirstChild(row.Key)
		if not item then
			continue
		end
		Authored.SetPair(item:FindFirstChild("Txt"), row.Label)
		Authored.SetPair(item:FindFirstChild("Num"), tostring(day.Summary[row.Key] or 0))
	end
	Authored.SetPair(Authored.Resolve(self.Panel, { "Top", "DailyReport", "Num" }), `# {day.Number}`)
	Authored.SetPair(
		Authored.Resolve(self.Panel, { "DailyProfit", "Value", "Num" }),
		string.format("%.2f", day.Summary.Coins)
	)
end

function ReportHandler.RefreshPhase(self: ReportHandler, phase: string?): ()
	if phase == "Summary" then
		self:Refresh()
		if self.Modal then
			return
		end
		self.Modal = true
		Pages.SetLocked(true, EVENING_PAGES)
		Pages.Open("Report")
		return
	end
	if phase == "Closing" then
		UIHandler:Toast("Closed for new guests. Finish serving the remaining orders.")
	end
	if not self.Modal then
		return
	end
	self.Modal = false
	Pages.SetLocked(false)
	if EVENING_PAGES[Pages.Current:peek()] then
		Pages.Close()
	end
end

function ReportHandler.Destroy(self: ReportHandler): ()
	self.Janitor:Destroy()
end

export type ReportHandler = typeof(ReportHandler) & {
	Janitor: any,
	Panel: Instance,
	Content: Instance,
	Modal: boolean,
}
return ReportHandler :: ReportHandler
