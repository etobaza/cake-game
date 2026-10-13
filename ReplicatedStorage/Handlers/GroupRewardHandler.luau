--!strict
-- The topbar's group reward button (Configs/Rewards.Group).
--
-- A click opens Roblox's own join prompt. Once the player is a member the client only asks for the
-- reward: the server checks membership itself, writes the claim flag and pays. The button leaves
-- the topbar when that saved flag replicates, so a claimed account never sees it again.

--[[ Services ]]--
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Handlers = ReplicatedStorage.Handlers

--[[ Modules ]]--
local Bus = require(_Shared.Bus)
local DataClient = require(_Handlers.DataHandlerClient)
local Rewards = require(_Shared.Configs.Rewards)
local TopbarHandler = require(_Handlers.TopbarHandler)
local UIHandler = require(_Handlers.UIHandler)

--[[ Constants ]]--
local ACTION_KEY = "GroupReward"
local LABEL = "Group Reward"
local CAPTION = `Join our group: +{Rewards.Group.Reward.Cash} coins`
-- After Daily Rewards (1) and Codes (2).
local ORDER = 3
local PENDING_TEXT = "Join request sent. Claim the reward once it is accepted"
local FAILED_TEXT = "The group prompt is unavailable right now. Try again soon"

--[[ Tables ]]--
local GroupRewardHandler = {
	dependencies = { "DataClient", "TopbarHandler", "UIHandler" },
	priority = 0,
}

--[[ Handling ]]--
function GroupRewardHandler.OnInit(self: GroupRewardHandler): ()
	self.Busy = false
	self.Shown = nil
end

function GroupRewardHandler.OnStart(self: GroupRewardHandler): ()
	TopbarHandler:CreateAction(ACTION_KEY, LABEL, CAPTION, ORDER, function(): ()
		self:Activate()
	end)

	self:Refresh()
	-- DataUpdated fires after the ready flag is set; CloudDataUpdated fires before it, so the first
	-- snapshot would read as not ready and hide the button until the next Cloud write.
	DataClient:SubscribeToAll(function(): ()
		self:Refresh()
	end)
end

--- Shows the button only once the profile is known and the reward is still unclaimed.
function GroupRewardHandler.Refresh(self: GroupRewardHandler): ()
	local claimed = DataClient:IsReady() and DataClient:GetData({ "Rewards", "GroupClaimed" }) == true
	local shown = DataClient:IsReady() and not claimed
	if shown == self.Shown then
		return
	end

	self.Shown = shown
	TopbarHandler:SetActionShown(ACTION_KEY, shown)
end

--- One join prompt at a time. Joined or already a member asks the server for the reward; a pending
--- join request (a group with manual approval) only explains why nothing was paid yet.
function GroupRewardHandler.Activate(self: GroupRewardHandler): ()
	if self.Busy then
		return
	end
	self.Busy = true

	task.spawn(function(): ()
		local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, Rewards.Group.GroupId)
		self.Busy = false

		if not ok then
			print(`[GroupRewardHandler] Join prompt failed: {status}`)
			UIHandler:Toast(FAILED_TEXT)
			return
		end

		if status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
			Bus.Progress.ClaimGroup:Fire()
		elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
			UIHandler:Toast(PENDING_TEXT)
		end
	end)
end

export type GroupRewardHandler = typeof(GroupRewardHandler) & {
	Busy: boolean,
	Shown: boolean?,
}

return GroupRewardHandler :: GroupRewardHandler
