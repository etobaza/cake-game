--!strict
-- Assistant: picks the one job the helper does for the whole day.
-- The server owns the rules (upgrade bought, evening planning only), this only shows and sends the pick.
--
-- Bind only an explicitly authored assistant control. The evening header belongs to
-- Report / Menu / Next Day navigation, including templates with duplicate Report names.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Authored = require(_Shared.UI.Authored)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local Press = require(_Shared.UI.Press)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local SCREEN_NAME = "Inventory"
local HEADER_PATH = { "MainFrame", "Header", "TopSection" }
local PLATE_NAME = "Assistant"
-- Upgrade that hires the assistant in the first place.
local ASSISTANT_UPGRADE = "cafe_assistant"

--[[ Tables ]]--
-- Every job the server understands, in the order the button walks through them. Adding one here is
-- the whole change.
local TASKS: { { Id: string, Name: string, Info: string } } = {
	{ Id = "None", Name = "Day off", Info = "The assistant does nothing today" },
	{ Id = "Tables", Name = "Clear tables", Info = "Cleans a dirty table every few seconds" },
	{ Id = "Coffee", Name = "Serve coffee", Info = "Carries ready coffee to the guest who ordered it" },
	{ Id = "Display", Name = "Stock the display", Info = "Moves finished dishes from the stations to the display" },
}

local AssistantHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
local function IsHired(): boolean
	local levels = DataClient:GetData({ "Base", "Upgrades" }) or {}

	return (levels[ASSISTANT_UPGRADE] or 0) > 0
end

local function IsPlanning(): boolean
	return DataClient:GetData({ "Day", "Phase" }, "Session") == "Summary"
end

local function CurrentTask(): { Id: string, Name: string, Info: string }
	local taskId = DataClient:GetData({ "AssistantTask" }) or "None"

	for _, task in TASKS do
		if task.Id == taskId then
			return task
		end
	end

	return TASKS[1]
end

local function NextTask(): { Id: string, Name: string, Info: string }
	local current = CurrentTask()

	for index, task in TASKS do
		if task.Id == current.Id then
			return TASKS[index % #TASKS + 1]
		end
	end

	return TASKS[1]
end

--[[ Handling ]]--
function AssistantHandler.OnStart(self: AssistantHandler): ()
	local screen = UIHandler:GetPanel(SCREEN_NAME)
	local header = screen and Authored.Resolve(screen, HEADER_PATH)
	local plate = header and header:FindFirstChild(PLATE_NAME)
	if not plate or not plate:IsA("GuiObject") then
		return
	end

	self.Plate = plate

	Press.Bind(plate, function()
		self:Advance()
	end)

	DataClient:WaitForData()
	self:Refresh()

	DataClient:SubscribeToPath({ "AssistantTask" }, function()
		self:Refresh()
	end, "Cloud")

	DataClient:SubscribeToPath({ "Base", "Upgrades" }, function()
		self:Refresh()
	end, "Cloud", true)

	DataClient:SubscribeToPath({ "Day", "Phase" }, function()
		self:Refresh()
	end, "Session")
end

--- The plate always says what the helper is doing, so the state is readable without opening anything.
function AssistantHandler.Refresh(self: AssistantHandler): ()
	local text = if IsHired() then `Helper: {CurrentTask().Name}` else "Helper: not hired"

	Authored.SetPair(self.Plate:FindFirstChild("Txt"), text)
end

--- Moves the helper to the next job. Refused here rather than by the server: the answer would be the
--- same toast either way.
function AssistantHandler.Advance(_self: AssistantHandler): ()
	if not IsHired() then
		UIHandler:Toast("Hire an assistant in Upgrades first")
		return
	end

	if not IsPlanning() then
		UIHandler:Toast("Plan the assistant's next job after closing")
		return
	end

	local task = NextTask()

	Bus.Progress.SetAssistantTask:Fire(task.Id)
	UIHandler:Toast(task.Info)
end

export type AssistantHandler = typeof(AssistantHandler) & {
	Plate: GuiObject,
}

return AssistantHandler :: AssistantHandler
