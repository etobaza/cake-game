--!strict
-- Success feedback on the owner's screen: coins flying from a sold dish into the HUD balance, the
-- floating amount with its grade and streak, the streak flame and its milestone banner, the level-up
-- banner, and bursts for purchases. It only presents what the server already accepted; world bursts
-- for everyone go through VFXHandler.

--[[ Services ]]--
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Bus = require(_Shared.Bus)
local CoinFlight = require(script.CoinFlight)
local Config = require(_Shared.Configs.Feedback)
local DataClient = require(_Handlers.DataHandlerClient)
local Economy = require(_Shared.Configs.Economy)
local Format = require(_Shared.UI.Format)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local LevelUp = require(script.LevelUp)
local Pages = require(_Shared.UI.Stores.Pages)
local Popup = require(script.Popup)
local Recipes = require(_Shared.Configs.Registries.Recipes)
local Sounds = require(_Shared.Configs.Sounds)
local SoundPlayer = require(_Shared.SoundPlayer)
local Sparks = require(_Shared.UI.Sparks)
local StreakBanner = require(script.StreakBanner)
local StreakMeter = require(script.StreakMeter)
local UIHandler = require(_Handlers.UIHandler)
local VFXHandler = require(_Handlers.VFXHandler)
local Wallet = require(_Shared.UI.Stores.Wallet)

--[[ Constants ]]--
local COIN_ICON_PATH = "Currency.Main.Icon"
-- Styles an unknown grade from a newer server.
local FALLBACK_GRADE: Config.Grade = "Great"
-- The level-up line lists at most this many unlocked recipes.
local MAX_UNLOCK_NAMES = 3
-- Glints where each coin lands.
local LANDING_TWINKLES = 2
local PURCHASE_FAN = 120
-- The streak flame snuffing out: the milestone whoosh, slowed and quiet.
local SNUFF_PITCH = 0.55
local SNUFF_VOLUME = 0.7

--[[ Tables ]]--
local FeedbackHandler = {
	-- The HUD coin is resolved through UIHandler; level ups burst through VFXHandler.
	dependencies = { "DataClient", "UIHandler", "VFXHandler" },
}

--[[ Private Functions ]]--
local function viewportScale(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else Config.ReferenceHeight
	return math.clamp(height / Config.ReferenceHeight, Config.MinScale, Config.MaxScale)
end

-- Absolute GUI point of a world position. Off-screen positions launch from the screen edge in their
-- direction, so money from the window counter still visibly arrives.
local function screenPoint(position: Vector3): Vector2
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector2.zero
	end
	local point, onScreen = camera:WorldToScreenPoint(position)
	if onScreen and point.Z > 0 then
		return Vector2.new(point.X, point.Y)
	end
	local relative = camera.CFrame:PointToObjectSpace(position)
	local direction = Vector2.new(relative.X, -relative.Y)
	if direction.Magnitude < 1e-3 then
		direction = Vector2.new(0, 1)
	end
	local inset = GuiService:GetGuiInset()
	local viewport = camera.ViewportSize
	local center = viewport / 2 - inset
	return center + direction.Unit * math.min(viewport.X, viewport.Y) * Config.Coins.EdgeInset
end

-- True while `gui` and every screen and frame above it are visible.
local function isShown(gui: GuiObject): boolean
	local current: Instance? = gui
	while current and not current:IsA("PlayerGui") do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return current ~= nil
end

local function unlockLine(level: number): string
	local names: { string } = {}
	for _, recipe in Recipes:GetUnlockedAt(level) do
		if #names >= MAX_UNLOCK_NAMES then
			break
		end
		table.insert(names, recipe.name)
	end
	if #names == 0 then
		return ""
	end
	if #names == 1 then
		return string.format(Config.LevelUp.UnlockSingle, names[1])
	end
	return string.format(Config.LevelUp.UnlockMany, table.concat(names, ", "))
end

-- Listed milestones, then every `MilestoneEvery` sales past the last one.
local function isMilestone(streak: number): boolean
	local milestones = Config.Streak.Milestones
	if table.find(milestones, streak) then
		return true
	end
	local last = milestones[#milestones]
	return streak > last and (streak - last) % Config.Streak.MilestoneEvery == 0
end

local function milestoneTitle(streak: number): string
	local title = ""
	for _, entry in Config.Streak.Titles do
		if streak >= entry.From then
			title = entry.Text
		end
	end
	return title
end

--[[ Handling ]]--
function FeedbackHandler.OnStart(self: FeedbackHandler): ()
	self.Janitor = Janitor.new()
	self.Popups = {}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- A transient overlay of our own: it never touches the authored screens it draws over.
	local screen = Instance.new("ScreenGui")
	screen.Name = "FeedbackOverlay"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.DisplayOrder = Config.DisplayOrder
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = screen
	screen.Parent = playerGui
	self.Janitor:Add(screen, "Destroy")
	self.Root = root

	local popups = Instance.new("Folder")
	popups.Name = "FeedbackPopups"
	popups.Parent = playerGui
	self.Janitor:Add(popups, "Destroy")
	self.PopupFolder = popups

	local found, icon = pcall(function(): Instance
		return UIHandler:GetHud(COIN_ICON_PATH)
	end)
	self.CoinIcon = if found and icon:IsA("GuiObject") then icon else nil
	if not self.CoinIcon then
		print(`[FeedbackHandler] HUD coin {COIN_ICON_PATH} is missing; sales skip the coin flight`)
	end

	self.Sparks = Sparks.new(root)
	self.Coins = CoinFlight.new(root, function(): (Vector2?, Vector2?)
		return self:CoinTarget()
	end)
	self.LevelUp = LevelUp.new(root, self.Sparks)
	self.Banner = StreakBanner.new(root, self.Sparks)
	self.PendingBanner = nil
	self.Meter = StreakMeter.new(root, function(): (Vector2?, Vector2?)
		return self:CoinTarget()
	end, self.Sparks)
	self.Janitor:Add(function(): ()
		-- Landing every coin releases the balance they still hold.
		self.Coins:Destroy()
		self.Sparks:Destroy()
		self.LevelUp:Destroy()
		self.Banner:Destroy()
		self.Meter:Destroy()
		for _, popup in self.Popups do
			popup:Destroy()
		end
		table.clear(self.Popups)
	end, true)

	self.Janitor:Add(
		Bus.Cafe.Sale.OnClientEvent:Connect(
			function(
				coins: number,
				streakBonus: number,
				grade: string,
				streak: number,
				record: boolean,
				head: Instance?,
				position: Vector3,
				cash: number
			): ()
				self:PlaySale(coins, streakBonus, grade, streak, record, head, position, cash)
			end
		),
		"Disconnect"
	)
	self.Janitor:Add(
		Bus.Cafe.StreakLost.OnClientEvent:Connect(function(lost: number): ()
			self:LoseStreak(lost)
		end),
		"Disconnect"
	)
	-- The replicated streak drives the flame; the initial snapshot shows it without a punch.
	DataClient:WaitForData()
	self.Meter:Set(DataClient:GetData({ "Streak" }, "Session") or 0, os.clock())
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Streak" }, function(value: any): ()
			self.Meter:Set(if typeof(value) == "number" then value else 0, os.clock())
		end, "Session"),
		"Disconnect"
	)
	self.Janitor:Add(
		Bus.Day.LevelUp.OnClientEvent:Connect(function(level: number): ()
			self:PlayLevelUp(level)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		RunService.RenderStepped:Connect(function(deltaTime: number): ()
			self:Step(deltaTime)
		end),
		"Disconnect"
	)
end

--- Absolute centre and size of the HUD coin, or nil while a page covers the HUD.
function FeedbackHandler.CoinTarget(self: FeedbackHandler): (Vector2?, Vector2?)
	local icon = self.CoinIcon
	if not icon or not icon.Parent or Pages.Current:peek() ~= Pages.Names.None then
		return nil, nil
	end
	local size = icon.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil, nil
	end
	return icon.AbsolutePosition + size / 2, size
end

function FeedbackHandler.PlaySale(
	self: FeedbackHandler,
	coins: number,
	streakBonus: number,
	grade: string,
	streak: number,
	record: boolean,
	head: Instance?,
	position: Vector3,
	cash: number
): ()
	local style = Config.Grades[grade :: Config.Grade] or Config.Grades[FALLBACK_GRADE]
	local tuning = Config.Streak
	-- The register climbs with the streak, so a run of good service sounds like it.
	local pitch = math.min(1 + math.max(streak - 1, 0) * tuning.PitchStep, tuning.PitchMax)
	local register = SoundPlayer.Play("CashRegister", nil, pitch)
	register.Volume *= style.RegisterVolume
	if style.Flourish then
		SoundPlayer.Play(style.Flourish, nil, pitch)
	end
	if record then
		SoundPlayer.Play("NewRecord")
	end

	local percent = math.round(streakBonus * 100)
	local streakLine: string? = nil
	if streak >= tuning.ShowFrom then
		streakLine = if percent > 0
			then string.format(tuning.Format, streak, percent)
			else string.format(tuning.FormatNoBonus, streak)
	end
	local adornee = if head and head:IsA("BasePart") and head:IsDescendantOf(workspace) then head else nil
	table.insert(
		self.Popups,
		Popup.new(self.PopupFolder, adornee, position, {
			Style = style,
			Amount = `+{Format.Number(coins)}$`,
			Streak = streakLine,
			Record = if record then tuning.RecordText else nil,
			Scale = viewportScale() * style.Scale,
		})
	)

	self:LaunchCoins(coins, cash, position, pitch)
	if streak > 0 and isMilestone(streak) then
		self:PlayMilestone(streak)
	end
end

--- A streak milestone: the fire banner (after a level-up banner that is still up), its sounds and a
--- fire ring at the character's feet.
function FeedbackHandler.PlayMilestone(self: FeedbackHandler, streak: number): ()
	local banner = Config.Streak.Banner
	local nextBonus = math.round(Economy.GetStreakTipBonus(streak) * 100)
	self.PendingBanner = {
		Title = milestoneTitle(streak),
		Run = string.format(banner.SubtitleFormat, streak, nextBonus),
	}
	SoundPlayer.Play("StreakMilestone")
	SoundPlayer.Play("FireWhoosh")

	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid then
		local feet = root.CFrame * CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight), 0)
		VFXHandler:Burst(banner.Effect, nil, feet, player.UserId, workspace:GetServerTimeNow())
	end
end

--- A mistake ended a run of `lost`; short runs end quietly.
function FeedbackHandler.LoseStreak(self: FeedbackHandler, lost: number): ()
	if lost < Config.Streak.LoseFrom then
		return
	end
	self.Meter:Lose(lost, os.clock())
	local snuff = SoundPlayer.Play("FireWhoosh", nil, SNUFF_PITCH)
	snuff.Volume *= SNUFF_VOLUME
end

--- Coins for `amount` fly into the HUD; the balance holds that amount back until they land.
function FeedbackHandler.LaunchCoins(
	self: FeedbackHandler,
	amount: number,
	cash: number,
	position: Vector3,
	pitch: number
): ()
	local _, size = self:CoinTarget()
	if not size then
		return
	end
	local tuning = Config.Coins
	local wanted = math.clamp(math.round(tuning.Base + amount * tuning.PerCoin), tuning.Min, tuning.Max)
	local count = math.min(wanted, tuning.MaxActive - self.Coins:Count())
	if count <= 0 then
		return
	end

	local sale = Wallet.Begin(amount, cash, tuning.HoldSeconds)
	local landed = 0
	self.Coins:Launch(screenPoint(position), count, function(index: number): ()
		landed += 1
		if landed >= count then
			Wallet.Finish(sale)
		else
			Wallet.Land(sale, amount / count)
		end
		local tick = math.min(tuning.TickPitch + (index - 1) * tuning.TickPitchStep, tuning.TickPitchMax)
		SoundPlayer.Play("Coin", nil, tick * pitch)
		local icon = self.CoinIcon
		if icon then
			Animate.Pop(icon, tuning.IconPopFrom)
		end
		local target = self:CoinTarget()
		if target then
			self.Sparks:Twinkle(target, LANDING_TWINKLES)
		end
	end)
end

function FeedbackHandler.PlayLevelUp(self: FeedbackHandler, level: number): ()
	-- Several levels at once replay the banner with the final number but one fanfare.
	if not self.LevelUp:IsShowing() then
		SoundPlayer.Play("LevelUp")
		SoundPlayer.Play("Pop")
	end
	self.LevelUp:Show(level, unlockLine(level), viewportScale())

	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		VFXHandler:Burst(Config.LevelUp.Effect, root, root.CFrame, player.UserId, workspace:GetServerTimeNow())
	end
end

--- A burst over any GUI element, such as a freshly bought upgrade node, with an optional sound.
--- Changes behind a closed page (an admin grant, a skip purchase) stay quiet.
function FeedbackHandler.Celebrate(self: FeedbackHandler, target: GuiObject, sound: Sounds.SoundName?): ()
	if not isShown(target) then
		return
	end
	if sound then
		SoundPlayer.Play(sound)
	end
	local center = target.AbsolutePosition + target.AbsoluteSize / 2
	self.Sparks:Twinkle(center, Config.Celebrate.Sparkles)
	self.Sparks:Confetti(center, Config.Celebrate.Confetti, PURCHASE_FAN)
end

function FeedbackHandler.Step(self: FeedbackHandler, deltaTime: number): ()
	local now = os.clock()
	local scale = viewportScale()
	self.Sparks:SetScale(scale)
	self.Coins:SetScale(scale)
	self.Coins:Step(now)
	self.Sparks:Step(deltaTime)
	self.LevelUp:Step(now)
	-- A milestone waits for a level-up banner that occupies the same space.
	local pending = self.PendingBanner
	if pending and not self.LevelUp:IsShowing() then
		self.PendingBanner = nil
		self.Banner:Show(pending.Title, pending.Run, scale)
	end
	self.Banner:Step(now)
	self.Meter:Step(now, scale)
	for index = #self.Popups, 1, -1 do
		local popup = self.Popups[index]
		if not popup:Step(now) then
			popup:Destroy()
			table.remove(self.Popups, index)
		end
	end
	Wallet.Expire(now)
end

function FeedbackHandler.Destroy(self: FeedbackHandler): ()
	self.Janitor:Destroy()
end

export type FeedbackHandler = typeof(FeedbackHandler) & {
	Janitor: any,
	Root: Frame,
	PopupFolder: Folder,
	CoinIcon: GuiObject?,
	Coins: CoinFlight.CoinFlight,
	Sparks: Sparks.Sparks,
	LevelUp: LevelUp.LevelUp,
	Banner: StreakBanner.StreakBanner,
	PendingBanner: { Title: string, Run: string }?,
	Meter: StreakMeter.StreakMeter,
	Popups: { Popup.Popup },
}

return FeedbackHandler :: FeedbackHandler
