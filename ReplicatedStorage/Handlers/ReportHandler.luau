--!strict
-- Drives StarterGui.Report and owns the evening modal across report, menu and upgrades. Also
-- announces the lunch rush and closing time, like Lemon Cake's stage notifications.
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
local DayCycleConfig = require(_Shared.Configs.DayCycle)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(_Shared.UI.Stores.Pages)
local Responsive = require(_Shared.UI.Responsive)
local UIHandler = require(_Handlers.UIHandler)
local Upgrades = require(_Shared.Configs.Registries.Upgrades)

--[[ Constants ]]--
local EVENING_PAGES: { [string]: boolean } = { Report = true, Upgrades = true, Inventory = true }
local REPORT_ROWS = table.clone(Config.Rows)
table.insert(REPORT_ROWS, Config.UpgradeRow)
local LUNCH_TEXT = "Lunch rush! Guests arrive faster now."
local ROW_GAP = 8
local ROW_SIDE_PADDING = 20
local ROW_NUMBER_WIDTH = 72
local ROW_TEXT_GAP = 12
local ROW_TEXT_SIZE = 32
local HEADING_TEXT_SIZE = 34
local SHORT_ROW_HEIGHT = 48

--[[ Tables ]]--
local ReportHandler = {
	-- Evening destinations hydrate their content before the modal opens navigation.
	dependencies = { "DataClient", "UIHandler", "MenuHandler", "ShopHandler" },
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
	-- Reserve a usable scroll viewport on the 300px landscape canvas. The tall layout's
	-- fixed heading and profit sections otherwise leave only one clipped line of rows.
	local shortLayout: { [string]: { Size: UDim2, Position: UDim2 } } = {
		Top = { Size = UDim2.new(1, -48, 0, 46), Position = UDim2.new(0.5, 0, 0, 77) },
		Middle = { Size = UDim2.new(1, -44, 1, -168), Position = UDim2.new(0.5, 0, 0, 108) },
		DailyProfit = { Size = UDim2.new(1, -44, 0, 44), Position = UDim2.new(0.5, 0, 1, -8) },
	}
	for name, geometry in shortLayout do
		local section = panel:FindFirstChild(name)
		if section and section:IsA("GuiObject") then
			section:SetAttribute("ShortSize", geometry.Size)
			section:SetAttribute("ShortPosition", geometry.Position)
		end
	end
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ScrollBarThickness = 6
	-- Rows added after the screen was drawn copy an authored row's styling.
	for _, row in REPORT_ROWS do
		local template = if row.Template then content:FindFirstChild(row.Template) else nil
		if not content:FindFirstChild(row.Key) and template then
			local copy = template:Clone()
			copy.Name = row.Key
			Authored.SetPair(copy:FindFirstChild("Txt"), row.Label)
			copy.Parent = content
		end
	end
	local rowCount = #REPORT_ROWS
	local rowSize = UDim2.new(1, -4, 1 / rowCount, -math.ceil(ROW_GAP * (rowCount - 1) / rowCount))
	for index, row in REPORT_ROWS do
		local item = content:FindFirstChild(row.Key)
		if not item or not item:IsA("GuiObject") then
			continue
		end
		item.LayoutOrder = index
		item.Size = rowSize
		item:SetAttribute("WideSize", rowSize)
		item:SetAttribute("CompactSize", rowSize)
		item:SetAttribute("ShortSize", UDim2.new(1, -4, 0, SHORT_ROW_HEIGHT))
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
		heading:SetAttribute("ShortSize", UDim2.new(heading.Size.X.Scale, heading.Size.X.Offset, 1, -4))
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
		print("[ReportHandler] StarterGui.Report.MainFrame.Middle.Container.Content is missing")
		return
	end
	self.Janitor = Janitor.new()
	self.Janitor:LinkToInstance(screen)
	self.Panel = panel
	self.Content = content
	self.Modal = false
	prepareLayout(screen, panel, content)
	local function refreshCanvas(): ()
		-- The landscape report scrolls full-height text rows; taller screens still show all rows together.
		content.CanvasSize = if screen:GetAttribute("Short") == true
			then UDim2.fromOffset(0, #REPORT_ROWS * SHORT_ROW_HEIGHT + (#REPORT_ROWS - 1) * ROW_GAP)
			else UDim2.fromScale(0, 0)
	end
	self.Janitor:Add(screen:GetAttributeChangedSignal("Short"):Connect(refreshCanvas), "Disconnect")
	refreshCanvas()
	DataClient:WaitForData()
	self.Janitor:Add(
		DataClient:SubscribeToDataType("Cloud", function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
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
	for _, field in { "EndsAt", "ShiftSeconds" } do
		self.Janitor:Add(
			DataClient:SubscribeToPath({ "Day", field }, function(): ()
				self:ScheduleLunch()
			end, "Session"),
			"Disconnect"
		)
	end
	self.Janitor:Add(function(): ()
		if self.Modal then
			Pages.SetLocked(false)
		end
		if self.LunchTask then
			task.cancel(self.LunchTask)
		end
	end, true)
	self:RefreshPhase(DataClient:GetData({ "Day", "Phase" }, "Session"))
	self:ScheduleLunch()
end

-- Toasts the start of the lunch rush (Configs/DayCycle); a changed clock reschedules it.
function ReportHandler.ScheduleLunch(self: ReportHandler): ()
	if self.LunchTask then
		task.cancel(self.LunchTask)
		self.LunchTask = nil
	end
	local day = DataClient:GetData({ "Day" }, "Session")
	if not day or day.Phase ~= "Shift" or day.EndsAt <= 0 or day.ShiftSeconds <= 0 then
		return
	end
	local delay = day.EndsAt - day.ShiftSeconds * (1 - DayCycleConfig.LunchProgress) - workspace:GetServerTimeNow()
	if delay <= 0 then
		return
	end
	self.LunchTask = task.delay(delay, function(): ()
		self.LunchTask = nil
		UIHandler:Toast(LUNCH_TEXT)
	end)
end

function ReportHandler.Refresh(self: ReportHandler): ()
	local day = DataClient:GetData({ "Day" }, "Session")
	if not day or day.Phase ~= "Summary" then
		return
	end
	local progress = Upgrades:ReadProgress(DataClient)
	for _, row in REPORT_ROWS do
		local item = self.Content:FindFirstChild(row.Key)
		if not item then
			continue
		end
		Authored.SetPair(item:FindFirstChild("Txt"), row.Label)
		local value = if row.Key == Config.UpgradeRow.Key then progress.AffordableCount else day.Summary[row.Key] or 0
		Authored.SetPair(item:FindFirstChild("Num"), tostring(value))
	end
	Authored.SetPair(Authored.Resolve(self.Panel, { "Top", "DailyReport", "Num" }), `# {day.Number}`)
	Authored.SetPair(
		Authored.Resolve(self.Panel, { "DailyProfit", "Value", "Num" }),
		UIHandler:FormatNumber(day.Summary.Coins)
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
	LunchTask: thread?,
}
return ReportHandler :: ReportHandler
