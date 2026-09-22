--!strict
-- Binds the HUD authored in StarterGui to reactive nodes.
--
-- The layout is not built here and never should be: it stays in StarterGui where it can be drawn and
-- nudged in the editor. This module only says which element follows which value, so a redesign that
-- keeps the names keeps working without a code change.
--
-- Paths are the ones the authored tree already used, so they read the same as the old
-- UIHandler:GetHud calls did.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Animate = require(_Shared.UI.Animate)
local Flux = require(_Packages.flux)
local HudLayout = require(_Shared.UI.HudLayout)
local Press = require(_Shared.UI.Press)
local UITypes = require(_Shared.UI.Types)

--[[ Constants ]]--
local Find = Flux.Find
local edit = Flux.edit
-- Flux selectors are typed with generic intersections the current solver cannot instantiate from
-- a string; these aliases keep one honest signature each.
local findPath: (path: string) -> (props: { [any]: any }) -> any = Find.Path :: any
local findChild: (name: string) -> (props: { [any]: any }) -> any = Find.Child :: any

-- Day phases as the data names them, mapped to the clock art that lights for each.
local PHASE_ICONS: { [string]: string } = {
	Prep = "Closed",
	Shift = "Day",
	Closing = "Evening",
	Summary = "Evening",
}
local ICON_NAMES = { "Day", "Evening", "Night", "Closed" }
-- A gain is a nudge, not the full pop an appearing element gets.
local POP_FROM_GAIN = 1.12
-- Delay between one HUD group arriving and the next: a small parade instead of one block.
local INTRO_STAGGER = 0.08

-- HUD groups that ride in from the screen edges on spawn and leave while a page is open, each
-- through the edge it lives against. XP is a notification with its own slide, and Quests folds
-- below with its arrow.
local GROUPS: { { Name: string, Edge: string } } = {
	{ Name = "Hotbar", Edge = "Bottom" },
	{ Name = "Order", Edge = "Bottom" },
	{ Name = "Currency", Edge = "Left" },
	{ Name = "SideBtns", Edge = "Left" },
	{ Name = "Time", Edge = "Top" },
}

-- Buttons that take press-and-hover feedback, and the artwork the scale is applied to. The HUD
-- buttons are bare hitboxes laid over their art, so the art is what moves.
local PRESSABLE: { { Button: string, Target: string? } } = {
	{ Button = "SideBtns.Shop.Btn", Target = "SideBtns.Shop" },
	{ Button = "SideBtns.Upgrades.Btn", Target = "SideBtns.Upgrades" },
	-- The Rewards button is its own ImageButton (moved out of the artist's draft HUD), no Btn hitbox.
	{ Button = "SideBtns.Rewards", Target = "SideBtns.Rewards" },
	{ Button = "XP.Plus.Btn", Target = "XP.Plus" },
	{ Button = "Quests.Btn", Target = nil },
}

--[[ Types ]]--
export type Props = {
	-- The raw amount, not a string: the plate counts up to it, so it has to be a number.
	BalanceValue: UITypes.Reactive<number>,
	FormatBalance: (value: number) -> string,
	FriendBoost: UITypes.Reactive<string>,
	Time: UITypes.Reactive<string>,
	-- "Prep" | "Shift" | "Summary"; anything else lights the closed sign.
	Phase: UITypes.Reactive<string>,
	-- True while a running shift is nearly over: the clock plate knocks on every remaining second.
	TimeUrgent: UITypes.Reactive<boolean>,
	XPText: UITypes.Reactive<string>,
	XPVisible: UITypes.Reactive<boolean>,
	QuestText: UITypes.Reactive<string>,
	QuestCount: UITypes.Reactive<string>,
	QuestAlpha: UITypes.Reactive<number>,
	HasQuest: UITypes.Reactive<boolean>,
	-- Folds the quest panel off the right edge, leaving only the arrow on screen.
	QuestsCollapsed: UITypes.Reactive<boolean>,
	-- False while a page is open: the HUD groups leave through their edges and come back after.
	HudShown: UITypes.Reactive<boolean>,
	LevelText: UITypes.Reactive<string>,
	LevelAlpha: UITypes.Reactive<number>,
	-- What the left side shop button is called.
	ShopLabel: UITypes.Reactive<string>,
	OnShop: (() -> ())?,
	OnTime: (() -> ())?,
	OnUpgrades: (() -> ())?,
	OnRewards: (() -> ())?,
	OnXPPlus: (() -> ())?,
	OnQuestsToggle: (() -> ())?,
}

--[[ Private Functions ]]--
-- Reads a Reactive<T> inside an effect: calls a function prop, unwraps a node, passes a value through.
local function read(value: any): any
	return if typeof(value) == "function" then value() else Flux.read(value)
end

-- Parks `group` past `edge` and springs it between home and parked as `shown` flips. The first
-- spring is held back by `delay`, so the HUD arrives as a parade rather than one block; a flip that
-- lands during the delay is caught up on, not lost.
local function home(group: GuiObject): UDim2
	return (group:GetAttribute("HomePosition") :: UDim2?) or group.Position
end

local function slideGroup(group: GuiObject, edge: string, delay: number, shown: UITypes.Reactive<boolean>): ()
	local progress = 1
	local function draw(): ()
		local base = home(group)
		local parent = group.Parent :: GuiObject
		local span = parent.AbsoluteSize
		local offset = if edge == "Left"
			then UDim2.fromOffset(-span.X, 0)
			elseif edge == "Top" then UDim2.fromOffset(0, -span.Y)
			else UDim2.fromOffset(0, span.Y)
		group.Position = base
			+ UDim2.new(
				offset.X.Scale * progress,
				offset.X.Offset * progress,
				offset.Y.Scale * progress,
				offset.Y.Offset * progress
			)
	end
	local motion = Animate.Track(group, "HudSlide", 1, function(value: number)
		progress = value
		draw()
	end)
	Flux.cleanup(group:GetAttributeChangedSignal("HomePosition"):Connect(draw))
	Flux.cleanup((group.Parent :: GuiObject):GetPropertyChangedSignal("AbsoluteSize"):Connect(draw))
	draw()
	local target = 1
	local ready = false
	Flux(function()
		target = if read(shown) then 0 else 1
		if ready then
			motion:spring(target)
		end
	end, true)
	task.delay(delay, function()
		ready = true
		motion:spring(target)
	end)
end
-- Walks a dot path the way the authored tree is addressed elsewhere.
local function resolve(root: Instance, path: string): Instance?
	local current: Instance = root

	for _, segment in string.split(path, ".") do
		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end
		current = child
	end

	return current
end

-- Outlined labels are a pair: the outer label is the dark plate, the nested `Inside` is the face.
-- Writing only one of them makes the outline drift away from the text.
--
-- Not every label was drawn as a pair, and a selector that finds nothing raises, so the nested
-- half is only asked for where it was actually drawn.
local function label(root: Instance, path: string, text: UITypes.Reactive<string>)
	local instance = resolve(root, path)

	if not instance or not instance:FindFirstChild("Inside") then
		return findPath(path)({ Text = text })
	end

	-- Flux props tables carry children in the array part by design.
	-- selene: allow(mixed_table)
	return findPath(path)({
		Text = text,
		findChild("Inside")({ Text = text }),
	})
end

-- The authored bars grow from a fixed left edge while staying centre-anchored, which is what
-- Animate.Fill used to do by hand. The edge and the height are read off the instance once, so a bar
-- that gets moved or resized in the editor keeps behaving.
--
-- Resolved by hand rather than through a selector because those numbers have to be read before the
-- first binding runs, and a function prop is a computed with no arguments -- it never sees the
-- instance it is bound to.
local function fill(root: Instance, path: string, alpha: UITypes.Reactive<number>): ()
	local instance = resolve(root, path)
	if not instance or not instance:IsA("GuiObject") then
		warn(`[HydrateHud] no fill at '{path}'`)
		return
	end

	local left = instance.Position.X.Scale - instance.Size.X.Scale / 2
	local height = instance.Size.Y
	local anchorY = instance.Position.Y

	edit(instance)({
		Size = function(): UDim2
			return UDim2.new(math.clamp(Flux.read(alpha) :: number, 0, 1), 0, height.Scale, height.Offset)
		end,
		Position = function(): UDim2
			local value = math.clamp(Flux.read(alpha) :: number, 0, 1)
			return UDim2.new(left + value / 2, 0, anchorY.Scale, anchorY.Offset)
		end,
	})
end

--[[ Handling ]]--
--- Binds `hud` -- the HUD frame inside the authored UI screen -- to the props.
--- Call inside a Flux.scope; every binding is torn down with it.
return function(hud: Instance, props: Props): ()
	Flux.cleanup(HudLayout.Bind(hud :: GuiObject))
	edit(hud)({
		-- Currency. The balance itself is driven below, by a spring that counts to it.
		label(hud, "Currency.FriendBoost", props.FriendBoost),

		-- Clock
		label(hud, "Time.Time", props.Time),

		-- Experience: a notification plate. It slides in from the right with what was just earned
		-- and slides back out; the store button on it only answers while it is on screen.
		label(hud, "XP.Main.XP", props.XPText),
		findPath("XP.Plus.Btn")({ Activated = props.OnXPPlus }),

		-- Quests
		findPath("Quests.Container.Quest")({ Visible = props.HasQuest }),
		label(hud, "Quests.Container.Quest.Progress", props.QuestText),
		label(hud, "Quests.Container.Quest.ProgressBar.Progress", props.QuestCount),
		label(hud, "Quests.Container.Level.Progress", props.LevelText),

		-- Buttons
		label(hud, "SideBtns.Shop.Shop", props.ShopLabel),
		findPath("SideBtns.Shop.Btn")({ Activated = props.OnShop }),
		findPath("SideBtns.Upgrades.Btn")({ Activated = props.OnUpgrades }),
		findPath("SideBtns.Rewards")({ Activated = props.OnRewards }),
	})

	fill(hud, "Quests.Container.Quest.ProgressBar.Fill", props.QuestAlpha)
	fill(hud, "Quests.Container.Level.ProgressBar.Fill", props.LevelAlpha)

	-- Every HUD button answers the finger: shrinks under it, lifts on hover, springs back after.
	for _, entry in PRESSABLE do
		local button = resolve(hud, entry.Button)
		local target = if entry.Target then resolve(hud, entry.Target) else nil

		if button and button:IsA("GuiObject") then
			Animate.Press(button, if target and target:IsA("GuiObject") then target else nil)
		end
	end

	-- The HUD rides in from the screen edges on spawn and leaves the same way while a page is open.
	for index, entry in GROUPS do
		local group = resolve(hud, entry.Name)
		if group and group:IsA("GuiObject") then
			slideGroup(group, entry.Edge, (index - 1) * INTRO_STAGGER, props.HudShown)
		end
	end

	local quests = resolve(hud, "Quests")
	local arrow = resolve(hud, "Quests.Btn")
	if quests and quests:IsA("GuiObject") and arrow and arrow:IsA("GuiObject") then
		-- 0 = expanded, 1 = folded with the whole arrow visible, 2 = hidden for a page.
		-- Derive distances during drawing so resizing never leaves a stale fold ratio.
		local progress = 2
		local function draw(): ()
			local base = home(quests)
			local width = quests.AbsoluteSize.X
			local folded = math.max(0, width - arrow.AbsoluteSize.X)
			local offset = math.min(progress, 1) * folded + math.max(progress - 1, 0) * (width + 48 - folded)
			quests.Position = base + UDim2.fromOffset(offset, 0)
		end
		local slide = Animate.Track(quests, "SlideX", 2, function(value: number)
			progress = value
			draw()
		end)
		Flux.cleanup(quests:GetAttributeChangedSignal("HomePosition"):Connect(draw))
		Flux.cleanup(quests:GetPropertyChangedSignal("AbsoluteSize"):Connect(draw))
		Flux.cleanup(arrow:GetPropertyChangedSignal("AbsoluteSize"):Connect(draw))
		if props.OnQuestsToggle then
			Flux.cleanup(Press.BindTap(arrow, props.OnQuestsToggle))
		end
		local spin = Animate.Track(arrow, "Rotation", 0, function(value: number)
			arrow.Rotation = value
		end)
		draw()
		Flux(function()
			local collapsed = Flux.read(props.QuestsCollapsed)
			slide:spring(if not read(props.HudShown) then 2 elseif collapsed then 1 else 0)
			spin:spring(if collapsed then 180 else 0)
		end, true)
	end

	local experience = resolve(hud, "XP")
	if experience and experience:IsA("GuiObject") then
		experience.Visible = true
		local progress = 1
		local function draw(): ()
			local parent = experience.Parent :: GuiObject
			experience.Position = home(experience) + UDim2.fromOffset(parent.AbsoluteSize.X * progress, 0)
		end
		local slide = Animate.Track(experience, "SlideX", 1, function(value: number)
			progress = value
			draw()
		end)
		Flux.cleanup(experience:GetAttributeChangedSignal("HomePosition"):Connect(draw))
		Flux.cleanup((experience.Parent :: GuiObject):GetPropertyChangedSignal("AbsoluteSize"):Connect(draw))
		draw()
		Flux(function()
			slide:spring(if Flux.read(props.XPVisible) then 0 else 1)
		end, true)
	end
	-- Coins count up to the new balance rather than jumping, so a sale reads as a gain, and the
	-- plate punches on every change after the first -- the first one is just the balance loading.
	local balance = resolve(hud, "Currency.Main.CoinBalance")
	if balance and balance:IsA("TextLabel") then
		local inside = balance:FindFirstChild("Inside") :: TextLabel?
		local plate = balance.Parent :: GuiObject
		local seen = false

		Flux(function()
			local amount = Flux.read(props.BalanceValue) :: number

			Animate.Count(balance, amount, function(value: number)
				local text = props.FormatBalance(value)
				balance.Text = text

				if inside then
					inside.Text = text
				end
			end, 2)

			if seen then
				Animate.Pop(plate, POP_FROM_GAIN)
			end

			seen = true
		end, true)
	end

	-- The four clock icons are stacked and toggled, exactly as authored.
	for _, name in ICON_NAMES do
		local icon = resolve(hud, `Time.TimeIcons.{name}`)
		if icon then
			edit(icon)({
				Visible = function(): boolean
					return PHASE_ICONS[Flux.read(props.Phase) :: string] == name
				end,
			})
		end
	end

	-- The clock lives the day out loud, Lemon Cake style: a phase change punches the plate and
	-- swings the sign that lights up, like a shop sign flipped on its nail.
	local plate = resolve(hud, "Time")
	if plate and plate:IsA("GuiObject") then
		Animate.Press(plate)
		if props.OnTime then
			Flux.cleanup(Press.Bind(plate, props.OnTime))
		end

		local seenPhase: string? = nil

		Flux(function()
			local phase = Flux.read(props.Phase) :: string

			if seenPhase ~= nil and phase ~= seenPhase then
				Animate.Pop(plate, POP_FROM_GAIN)

				local icon = resolve(hud, `Time.TimeIcons.{PHASE_ICONS[phase]}`)
				if icon and icon:IsA("GuiObject") then
					Animate.Pop(icon)
					Animate.Swing(icon)
				end
			end

			seenPhase = phase
		end, true)

		-- The last real seconds of a shift knock on the plate: one nudge per displayed shop-clock
		-- minute, driven by the label changing rather than by every reactive clock tick underneath it.
		local seenTime: string? = nil

		Flux(function()
			local text = read(props.Time) :: string
			local urgent = read(props.TimeUrgent) == true

			if urgent and seenTime ~= nil and text ~= seenTime then
				Animate.Pop(plate, POP_FROM_GAIN)
			end

			seenTime = text
		end, true)
	end
end
