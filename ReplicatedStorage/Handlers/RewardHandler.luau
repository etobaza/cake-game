--!strict
-- The three reward screens: promo codes, the daily streak and playtime tiers.
--
-- Drives the Codes, DailyRewards and Playtime screens authored in StarterGui. All three were drawn
-- complete -- a code box with a Claim button, seven day tiles, fifteen playtime cells each with a
-- locked face, a ready button, a claimed mark and a timer -- so nothing is built here.
--
-- The client sends intent only. Every deadline is decided by the server; the countdowns below are
-- what the player reads, not what the grant is checked against.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local CardGrid = require(_Shared.UI.CardGrid)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Animate = require(_Shared.UI.Animate)
local Authored = require(_Shared.UI.Authored)
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local Format = require(_Shared.UI.Format)
local Press = require(_Shared.UI.Press)
local Rewards = require(_Configs.Rewards)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local CODES_SCREEN = "Codes"
local CODE_BOX = { "MainFrame", "Content", "Input", "Box" }
local CODE_BUTTON = { "MainFrame", "Content", "Redeem" }
local CODE_PLACEHOLDER = "Input code here.."

local DAILY_SCREEN = "DailyRewards"
local DAILY_GRID = { "MainFrame", "Content" }

local PLAYTIME_SCREEN = "Playtime"
local PLAYTIME_GRID = { "MainFrame", "Container", "Content" }

-- How often an open screen redraws its countdowns. One timer for the whole handler, not one per tile.
local TICK_SECONDS = 1

--[[ Tables ]]--
local RewardHandler = {
	dependencies = { "DataClient", "UIHandler" },
}

--[[ Private Functions ]]--
-- Direct authored tiles keep their reward order when the responsive grid reflows.
local function GridCells(grid: Instance): { Frame }
	local cells = {}
	for _, cell in grid:GetChildren() do
		if cell:IsA("Frame") then
			cells[#cells + 1] = cell
		end
	end
	table.sort(cells, function(left: Frame, right: Frame): boolean
		return left.LayoutOrder < right.LayoutOrder
	end)
	return cells
end
-- Beige is the plain face, Green the one behind a taken reward. The tile punches on the way over,
-- which is the whole of the "you got it" feedback on these screens.
local function SetFace(cell: Frame, claimed: boolean): ()
	local beige = cell:FindFirstChild("Beige")
	local green = cell:FindFirstChild("Green")

	if beige and beige:IsA("GuiObject") then
		beige.Visible = not claimed
	end

	if green and green:IsA("GuiObject") then
		green.Visible = claimed
	end

	if claimed and cell:GetAttribute("Claimed") ~= true then
		Animate.Pop(cell)
	end

	cell:SetAttribute("Claimed", claimed)
end

local function Claimed(list: any, index: number): boolean
	for _, value in list do
		if value == index then
			return true
		end
	end

	return false
end

--[[ Handling ]]--
function RewardHandler.OnStart(self: RewardHandler): ()
	self.Janitor = Janitor.new()
	self.DailyCells = {}
	self.PlaytimeCells = {}

	self:BindCodes()
	self:BindDaily()
	self:BindPlaytime()

	Bus.Progress.RewardGranted.OnClientEvent:Connect(function(message: string)
		UIHandler:Toast(message)
	end)

	DataClient:WaitForData()
	self:Refresh()

	DataClient:SubscribeToPath({ "Rewards" }, function()
		self:Refresh()
	end, "Cloud", true)

	DataClient:SubscribeToPath({ "Playtime" }, function()
		self:Refresh()
	end, "Session", true)

	-- The countdowns move on their own, so an open screen is redrawn once a second. Closed screens
	-- are skipped: nothing behind a disabled ScreenGui is worth the work.
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)

			if self.Daily and self.Daily.Enabled then
				self:RefreshDaily()
			end

			if self.Playtime and self.Playtime.Enabled then
				self:RefreshPlaytime()
			end
		end
	end)
end

function RewardHandler.BindCodes(self: RewardHandler): ()
	local screen = UIHandler:GetPanel(CODES_SCREEN)
	local box = screen and Authored.Resolve(screen, CODE_BOX)
	local button = screen and Authored.Resolve(screen, CODE_BUTTON)
	if not box or not box:IsA("TextBox") or not button or not button:IsA("GuiObject") then
		warn(`[RewardHandler] '{CODES_SCREEN}' has no code box; codes are disabled`)
		return
	end

	self.CodeBox = box

	local function redeem(): ()
		local code = box.Text
		if code == "" or code == CODE_PLACEHOLDER then
			UIHandler:Toast("Type a code first")
			return
		end

		Bus.Progress.RedeemCode:Fire(code)
		box.Text = ""
	end

	-- Bound through Press even though the plate is an ImageButton: some of the authored buttons were
	-- left with Active off, and a button that is not Active never fires Activated at all.
	Animate.Press(button)
	Press.BindTap(button, redeem)

	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			redeem()
		end
	end)
end

function RewardHandler.BindDaily(self: RewardHandler): ()
	local screen = UIHandler:GetPanel(DAILY_SCREEN)
	local grid = screen and Authored.Resolve(screen, DAILY_GRID)
	if not screen or not grid then
		warn(`[RewardHandler] '{DAILY_SCREEN}' has no tiles; the daily streak is disabled`)
		return
	end

	self.Janitor:Add(CardGrid.Bind(grid :: GuiObject), "Destroy")
	self.Daily = screen
	self.Janitor:LinkToInstance(screen)
	self.DailyCells = GridCells(grid)

	for _, cell in self.DailyCells do
		local claim = cell:FindFirstChild("Claim")
		if claim and claim:IsA("GuiObject") then
			Animate.Press(claim)
			Press.BindTap(claim, function()
				Bus.Progress.ClaimDaily:Fire()
			end)
		end
	end
end

function RewardHandler.BindPlaytime(self: RewardHandler): ()
	local screen = UIHandler:GetPanel(PLAYTIME_SCREEN)
	local grid = screen and Authored.Resolve(screen, PLAYTIME_GRID)
	if not screen or not grid then
		warn(`[RewardHandler] '{PLAYTIME_SCREEN}' has no tiles; playtime rewards are disabled`)
		return
	end

	self.Janitor:Add(CardGrid.Bind(grid :: GuiObject), "Destroy")
	self.Playtime = screen
	self.PlaytimeCells = GridCells(grid)

	for index, cell in self.PlaytimeCells do
		local claim = cell:FindFirstChild("ClaimButton")
		if claim and claim:IsA("GuiObject") then
			Animate.Press(claim)
			Press.BindTap(claim, function()
				Bus.Progress.ClaimPlaytime:Fire(index)
			end)
		end
	end
end

function RewardHandler.Refresh(self: RewardHandler): ()
	self:RefreshDaily()
	self:RefreshPlaytime()
end

--- A tile is either already taken, the one that can be taken now, or a wait.
function RewardHandler.RefreshDaily(self: RewardHandler): ()
	local record = DataClient:GetData({ "Rewards" }, "Cloud")
	local taken = if record then record.Day else 0
	local claimedAt = if record then record.ClaimedAt else 0
	-- The same rule the server applies, so the screen and the grant agree.
	local since = os.time() - claimedAt
	local ready = claimedAt == 0 or since >= Rewards.Daily.Cooldown
	local nextDay = if claimedAt == 0 or since > Rewards.Daily.Grace then 1 else taken + 1

	for index, cell in self.DailyCells do
		local reward = Rewards.GetDay(index)
		local isTaken = index <= taken and since <= Rewards.Daily.Grace
		local isNext = ready and index == nextDay

		SetFace(cell, isTaken)
		Authored.SetPair(cell:FindFirstChild("Name"), if reward then `{Format.Number(reward.Cash)}` else "-")

		local claim = cell:FindFirstChild("Claim")
		if claim and claim:IsA("GuiObject") then
			claim.Visible = isNext
		end
		local timer = cell:FindFirstChild("Timer")
		if timer and timer:IsA("GuiObject") then
			timer.Visible = not isNext
		end

		local timerText = if isTaken
			then "Claimed"
			elseif isNext then "Ready"
			elseif ready then `Day {index}`
			else Format.LongTime(Rewards.Daily.Cooldown - since)
		Authored.SetPair(cell:FindFirstChild("Timer"), timerText)
	end
end

function RewardHandler.RefreshPlaytime(self: RewardHandler): ()
	local record = DataClient:GetData({ "Playtime" }, "Session")
	local startedAt = if record then record.StartedAt else 0
	local claimed = if record then record.Claimed else {}
	local elapsed = if startedAt > 0 then workspace:GetServerTimeNow() - startedAt else 0

	for index, cell in self.PlaytimeCells do
		local reward = Rewards.GetTier(index)
		local due = Rewards.GetTierSeconds(index)
		local isTaken = Claimed(claimed, index)
		local isReady = not isTaken and elapsed >= due

		SetFace(cell, isTaken)
		Authored.SetPair(cell:FindFirstChild("Reward"), if reward then `{Format.Number(reward.Cash)}` else "-")

		local claim = cell:FindFirstChild("ClaimButton")
		if claim and claim:IsA("GuiObject") then
			claim.Visible = isReady
		end
		local timer = cell:FindFirstChild("Timer")
		if timer and timer:IsA("GuiObject") then
			timer.Visible = not isReady
		end

		local mark = cell:FindFirstChild("Mark")
		if mark and mark:IsA("GuiObject") then
			mark.Visible = isTaken
		end

		local timerText = if isTaken then "Claimed" elseif isReady then "Ready" else Format.Time(due - elapsed)
		Authored.SetPair(cell:FindFirstChild("Timer"), timerText)
	end
end

export type RewardHandler = typeof(RewardHandler) & {
	Janitor: any,
	CodeBox: TextBox?,
	Daily: ScreenGui?,
	Playtime: ScreenGui?,
	DailyCells: { Frame },
	PlaytimeCells: { Frame },
}

return RewardHandler :: RewardHandler
