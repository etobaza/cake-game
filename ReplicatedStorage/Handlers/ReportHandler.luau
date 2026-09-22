--!strict
-- Drives StarterGui.Report and owns the evening modal across report and menu.
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
local Responsive = require(_Shared.UI.Responsive)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local EVENING_PAGES: { [string]: boolean } = { Report = true, Inventory = true }
local ROW_GAP = 8
local ROW_SIDE_PADDING = 20
local ROW_NUMBER_WIDTH = 72
local ROW_TEXT_GAP = 12
local ROW_TEXT_SIZE = 32
local HEADING_TEXT_SIZE = 34

--[[ Tables ]]--
local ReportHandler = {
	-- Menu must have hydrated its recipe cells before the evening navigation opens it.
	dependencies = { "DataClient", "UIHandler", "MenuHandler" },
}

--[[ Private Functions ]]--
local function sizeText(holder: Instance?, maximum: number): ()
	if not holder then
		return
	end
	for _, label in holder:GetChildren() do
		if not label:IsA("TextLabel") then
			continue
		end
		label.TextScaled = true
		label.TextYAlignment = Enum.TextYAlignment.Center
		local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			-- Responsive keeps this baseline when the viewport changes.
			constraint:SetAttribute("AuthoredMaxTextSize", maximum)
			constraint.MaxTextSize = maximum
		end
	end
end

local function prepareLayout(screen: ScreenGui, panel: Instance, content: ScrollingFrame): ()
	local layout = content:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end
	-- The old dashed inset overlaps the first and last full-height report rows.
	local lines = Authored.Resolve(panel, { "Middle", "Lines" })
	if lines and lines:IsA("GuiObject") then
		lines.Visible = false
	end
	layout.Padding = UDim.new(0, ROW_GAP)
	-- All report rows share the available height, including on the compact canvas.
	-- A fixed canvas avoids feedback between scaled rows and AutomaticCanvasSize.
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.CanvasSize = UDim2.fromScale(0, 0)
	content.CanvasPosition = Vector2.zero
	local rowCount = #Config.Rows
	local rowSize = UDim2.new(1, -4, 1 / rowCount, -math.ceil(ROW_GAP * (rowCount - 1) / rowCount))
	for index, row in Config.Rows do
		local item = content:FindFirstChild(row.Key)
		if not item or not item:IsA("GuiObject") then
			continue
		end
		item.LayoutOrder = index
		item.Size = rowSize
		item:SetAttribute("WideSize", rowSize)
		item:SetAttribute("CompactSize", rowSize)
		local caption = item:FindFirstChild("Txt")
		local number = item:FindFirstChild("Num")
		if caption and caption:IsA("GuiObject") then
			caption.Position = UDim2.new(0, ROW_SIDE_PADDING, 0.5, 0)
			caption.Size = UDim2.new(1, -(2 * ROW_SIDE_PADDING + ROW_NUMBER_WIDTH + ROW_TEXT_GAP), 1, -12)
		end
		if number and number:IsA("GuiObject") then
			number.Position = UDim2.new(1, -ROW_SIDE_PADDING, 0.5, 0)
			number.Size = UDim2.new(0, ROW_NUMBER_WIDTH, 1, -12)
		end
		sizeText(caption, ROW_TEXT_SIZE)
		sizeText(number, ROW_TEXT_SIZE)
	end
	local heading = Authored.Resolve(panel, { "Top", "DailyReport", "Txt" })
	if heading and heading:IsA("GuiObject") then
		heading.Size = UDim2.new(heading.Size.X.Scale, heading.Size.X.Offset, 1, -16)
	end
	sizeText(heading, HEADING_TEXT_SIZE)
	sizeText(Authored.Resolve(panel, { "Top", "DailyReport", "Num" }), HEADING_TEXT_SIZE)
	sizeText(Authored.Resolve(panel, { "DailyProfit", "Title", "Txt" }), HEADING_TEXT_SIZE)
	sizeText(Authored.Resolve(panel, { "DailyProfit", "Value", "Num" }), HEADING_TEXT_SIZE)
	Responsive.Apply(screen)
end

--[[ Handling ]]--
function ReportHandler.OnStart(self: ReportHandler): ()
	local screen = UIHandler:GetPanel("Report")
	local panel = screen and screen:FindFirstChild("MainFrame")
	local content = panel and Authored.Resolve(panel, { "Middle", "Container", "Content" })
	if not screen or not panel or not content or not content:IsA("ScrollingFrame") then
		warn("[ReportHandler] StarterGui.Report.MainFrame.Middle.Container.Content is missing")
		return
	end
	self.Janitor = Janitor.new()
	self.Janitor:LinkToInstance(screen)
	self.Panel = panel
	self.Content = content
	self.Modal = false
	prepareLayout(screen, panel, content)
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
