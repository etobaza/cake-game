--!strict
-- Post-tutorial coaching. One situation at a time: a short cause-and-fix message first, a pointer
-- only if the player still hesitates. Progress restarts the wait; repeated refusals skip it.
-- Client-side memory only: nothing here changes saved progress.

--[[ Modules ]]--
local Assist = require(script.Parent.Assist)
local Config = require(script.Parent.Parent.Configs.Tutorial)
local Features = require(script.Parent.Features)
local Types = require(script.Parent.Parent.GameTypes)

--[[ Constants ]]--
local Settings = Config.Coach
local TOPIC = "Coach"

--[[ Tables ]]--
local Coach = {}
Coach.__index = Coach

export type Coach = typeof(setmetatable(
	{} :: {
		Key: string,
		Since: number,
		Signature: string,
		Nudged: boolean,
		Pointing: boolean,
		LastNudgeAt: number,
		Points: { [string]: number },
		Failures: { number },
		BoostUntil: number,
		Intros: { [string]: number },
		Active: boolean,
	},
	Coach
))

--[[ Private Functions ]]--
-- Player-made changes only: guests arriving or leaving do not count as the player's progress.
local function signature(session: any): string
	local parts = {}
	for _, item in session.Hands do
		parts[#parts + 1] = `{item.Kind}:{item.Id}`
	end
	local ids = {}
	for id in session.Stations do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ids do
		local station = session.Stations[id]
		local loaded = 0
		for _, amount in station.Loaded do
			loaded += amount
		end
		parts[#parts + 1] = `{id}:{station.State}:{loaded}`
	end
	local stocked, dirty, spills = 0, 0, 0
	for _ in session.Display do
		stocked += 1
	end
	for _ in session.Window do
		stocked += 1
	end
	for _, cafeTable in session.Tables do
		for _, seat in cafeTable.Seats do
			dirty += if seat.Dirty then 1 else 0
		end
	end
	for _ in session.Spills do
		spills += 1
	end
	local served = 0
	for _, customer in session.Customers do
		served += if customer.State == "Waiting" or customer.State == "Eating" then #customer.Orders + 1 else 0
	end
	parts[#parts + 1] = `{session.Cooking.SelectedRecipeId or ""}:{stocked}:{dirty}:{spills}:{served}`
	return table.concat(parts, "|")
end

type Profile = { Scale: number, Cooldown: number, PointsPerStep: number }

-- Fresh bakers get shorter waits and more pointers; the plain values apply afterwards.
local function profile(cloud: any): Profile
	local day = cloud.Day or 1
	local chosen: Profile = { Scale = 1, Cooldown = Settings.Cooldown, PointsPerStep = Settings.PointsPerStep }
	local bound = math.huge
	for _, row in Settings.Experience do
		if day <= row.MaxDay and row.MaxDay < bound then
			bound = row.MaxDay
			chosen = { Scale = row.Scale, Cooldown = row.Cooldown, PointsPerStep = row.PointsPerStep }
		end
	end
	return chosen
end

local function stepKind(step: Types.TutorialGoal): string
	return string.match(step.id, "^%a+") or step.id
end

local function nudge(situation: Types.CoachSituation): Types.TutorialGoal
	return {
		id = `coach_nudge:{situation.key}`,
		title = situation.message,
		hint = "",
		-- Waiting goals show the toast without the pressing finger.
		waiting = true,
		target = situation.anchor or (if situation.step then situation.step.target else nil),
		topic = TOPIC,
	}
end

local function point(situation: Types.CoachSituation, step: Types.TutorialGoal): Types.TutorialGoal
	local goal = table.clone(step)
	goal.id = `coach:{situation.key}`
	goal.topic = TOPIC
	-- Coaching never repeats its toast on the introduction's reminder timer.
	goal.urgent = nil
	return goal
end

--[[ Handling ]]--
function Coach.new(): Coach
	return setmetatable({
		Key = "",
		Since = 0,
		Signature = "",
		Nudged = false,
		Pointing = false,
		LastNudgeAt = -math.huge,
		Points = {},
		Failures = {},
		BoostUntil = 0,
		Intros = {},
		Active = false,
	}, Coach) :: Coach
end

-- A server refusal. Misunderstandings that repeat raise the help level immediately.
function Coach.Failed(self: Coach, code: string, clock: number): ()
	if not Settings.Confusion[code] then
		return
	end
	local recent = {}
	for _, at in self.Failures do
		if clock - at <= Settings.FailureWindow then
			recent[#recent + 1] = at
		end
	end
	recent[#recent + 1] = clock
	if #recent >= Settings.FailureCount then
		self.BoostUntil = clock + Settings.BoostSeconds
		recent = {}
	end
	self.Failures = recent
end

-- Whether a situation is waiting for its next help level, so the caller keeps refreshing.
function Coach.IsPending(self: Coach): boolean
	return self.Active
end

function Coach.Reset(self: Coach): ()
	self.Key = ""
	self.Nudged = false
	self.Pointing = false
	self.Active = false
end

function Coach.Select(
	self: Coach,
	cloud: any,
	session: any,
	props: { [string]: boolean },
	page: string,
	now: number,
	clock: number
): Types.CoachSituation?
	local phase = session.Day.Phase
	if phase == "Summary" then
		return Features.Summary(cloud, session, page) or Assist.Summary(session, page)
	end
	if page ~= "None" then
		return nil
	end
	if phase == "Prep" then
		for _, intro in Features.Intros(cloud, session) do
			local shownAt = self.Intros[intro.key]
			if not shownAt then
				self.Intros[intro.key] = clock
				return intro
			end
			if clock - shownAt < Config.Coach.IntroSeconds then
				return intro
			end
		end
	end
	return Features.Moment(cloud, session, props) or Assist.Resolve(cloud, session, props, now)
end

-- `now` is server time for kitchen timestamps; `clock` is local time for coaching waits.
function Coach.Update(
	self: Coach,
	cloud: any,
	session: any,
	props: { [string]: boolean },
	page: string,
	now: number,
	clock: number
): Types.TutorialGoal?
	if not Settings.Enabled then
		return nil
	end
	local situation = self:Select(cloud, session, props, page, now, clock)
	local current = signature(session)
	local progressed = current ~= self.Signature
	self.Signature = current
	if not situation then
		self:Reset()
		return nil
	end
	self.Active = true
	local delays = Settings.Delays[situation.delay]
	local level = profile(cloud)
	local scale = if situation.delay == "Feature" then 1 else level.Scale
	if situation.key ~= self.Key or (progressed and situation.delay ~= "Feature") then
		self.Key = situation.key
		self.Since = clock
		self.Nudged = false
		self.Pointing = false
	end

	local elapsed = clock - self.Since
	local boosted = clock < self.BoostUntil
	local step = situation.step
	if step and not step.waiting and not Settings.NudgeOnly[step.id] then
		local kind = stepKind(step)
		local allowed = self.Pointing or boosted or (self.Points[kind] or 0) < level.PointsPerStep
		-- The explanation always comes first, unless repeated refusals already showed it.
		if allowed and (self.Pointing or boosted or (self.Nudged and elapsed >= delays.Point * scale)) then
			if not self.Pointing then
				self.Pointing = true
				self.Points[kind] = (self.Points[kind] or 0) + 1
				self.BoostUntil = 0
			end
			return point(situation, step)
		end
	end
	if self.Nudged then
		return nudge(situation)
	end
	if elapsed < delays.Nudge * scale then
		return nil
	end
	if delays.Cooldown and not boosted and clock - self.LastNudgeAt < level.Cooldown then
		return nil
	end
	self.Nudged = true
	self.LastNudgeAt = clock
	return nudge(situation)
end

return Coach
