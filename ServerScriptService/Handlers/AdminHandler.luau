--!strict
-- Online support actions. No arbitrary data paths, code execution, or offline profile writes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local Handlers = ServerScriptService.Handlers
local Config = require(Shared.Configs.Admin)
local TutorialConfig = require(Shared.Configs.Tutorial)
local Bus = require(Shared.Bus)
local AdminRegistry = require(ServerScriptService.Cmdr.Admin)
local DataHandler = require(Handlers.DataHandler)
local EconomyHandler = require(Handlers.EconomyHandler)
local PantryHandler = require(Handlers.PantryHandler)
local InventoryHandler = require(Handlers.InventoryHandler)
local UpgradeHandler = require(Handlers.UpgradeHandler)
local TutorialHandler = require(Handlers.TutorialHandler)
local DayCycleHandler = require(Handlers.DayCycleHandler)
local Ingredients = require(Shared.Configs.Registries.Ingredients)
local Upgrades = require(Shared.Configs.Registries.Upgrades)
local Buildings = require(Shared.Configs.Buildings)
local Logger = require(Shared.Libs.Logger).new({ name = "AdminHandler" })

type Pending = { token: string, action: string, target: Player, amount: number, expires: number }
export type Reply = { ok: boolean, message: string, token: string? }

local lastRequest: { [Player]: number } = {}
local pending: { [Player]: Pending } = {}
local busy: { [Player]: boolean } = {}
local targetBusy: { [Player]: boolean } = {}
local audit: { string } = {}

local AdminHandler = {
	dependencies = {
		"DataHandler",
		"EconomyHandler",
		"PantryHandler",
		"InventoryHandler",
		"UpgradeHandler",
		"TutorialHandler",
		"DayCycleHandler",
	},
	priority = -10,
}

local function reply(ok: boolean, message: string): Reply
	return { ok = ok, message = message }
end

function AdminHandler.CanUse(_self: AdminHandler, player: Player): boolean
	return player.Parent == Players and (RunService:IsStudio() or AdminRegistry:IsAdmin(player.UserId))
end

local function inspect(target: Player): Reply
	local data = DataHandler:GetData(target)
	if not data then
		return reply(false, "Player data has not loaded yet.")
	end
	local cloud, session = data.Cloud, data.Session
	return reply(
		true,
		`@{target.Name} • ID {target.UserId}\nCoins: {cloud.Cash} • Level: {cloud.Level} • XP: {cloud.XP}\nDay: {cloud.Day} • Phase: {session.Day.Phase} • Tutorial: {cloud.Tutorial.Status}\nHeld items: {#session.Hands} • Reset pending: {tostring(
			cloud.ProgressResetPending
		)}`
	)
end

local function execute(action: string, target: Player, amount: number): Reply
	local data = DataHandler:GetData(target)
	if not data or data.Cloud.ProgressResetPending then
		return reply(
			false,
			"The profile is not ready or has a pending reset. Rejoin the game."
		)
	end
	if action == "addCash" or action == "setCash" or action == "upgradeMoney" then
		local before = EconomyHandler:GetCash(target)
		local after = amount
		if action == "addCash" then
			after = before + amount
		elseif action == "upgradeMoney" then
			after = math.max(before, Upgrades:GetRemainingCost(data.Cloud.Base.Upgrades))
		end
		if not EconomyHandler:SetAdminCash(target, after) then
			return reply(false, `Balance must be between 0 and {Config.MaxCash}.`)
		end
		return reply(
			true,
			`Coins: {before} → {after}. Paid multipliers do not apply.`
		)
	elseif action == "addXP" then
		EconomyHandler:AwardXP(target, amount)
		return reply(true, `Level: {data.Cloud.Level}; XP: {data.Cloud.XP}.`)
	elseif action == "stockPantry" then
		for _, ingredient in Ingredients:Values() do
			if
				not Ingredients:IsInfinite(ingredient.id)
				and PantryHandler:GetAmount(target, ingredient.id) + amount > Config.MaxPantry
			then
				return reply(false, `Stock limit: {Config.MaxPantry}. Nothing was granted.`)
			end
		end
		for _, ingredient in Ingredients:Values() do
			if not Ingredients:IsInfinite(ingredient.id) then
				PantryHandler:Add(target, ingredient.id, amount)
			end
		end
	elseif action == "unlockUpgrades" then
		local changed = UpgradeHandler:GrantAll(target)
		return reply(changed ~= nil, `Upgrades unlocked: {changed or 0}.`)
	elseif action == "skipTutorial" then
		if not TutorialHandler.Runs[target] then
			return reply(false, "The tutorial is not ready for this player yet.")
		end
		return reply(true, TutorialHandler:Finish(target, "Skipped"))
	elseif action == "resetTutorial" then
		if not TutorialHandler.Runs[target] then
			return reply(false, "The tutorial is not ready for this player yet.")
		end
		return reply(true, TutorialHandler:Reset(target))
	elseif action == "openBakery" or action == "endShift" or action == "nextDay" then
		local accepted = false
		if action == "openBakery" then
			accepted = DayCycleHandler:OpenBakery(target)
		elseif action == "endShift" then
			accepted = DayCycleHandler:EndShift(target)
		else
			accepted = DayCycleHandler:NextDay(target)
		end
		return reply(
			accepted,
			if accepted
				then `Phase: {data.Session.Day.Phase}.`
				else "Invalid phase or menu. Open during Prep; end during Shift; advance from Summary with a valid menu selected."
		)
	elseif action == "clearHands" then
		local held = InventoryHandler:Peek(target)
		if held and held.Kind == "Tool" then
			for _, kind in Buildings.Kinds do
				if kind.ToolId == held.Id and kind.Singles then
					for _, single in kind.Singles do
						InventoryHandler:ReturnTool(target, single.Id)
					end
				end
			end
		end
		InventoryHandler:Clear(target)
	elseif action == "respawn" then
		target:LoadCharacterAsync()
	elseif action == "resync" then
		DataHandler:ResendSnapshot(target)
	elseif action == "resetProgress" then
		return reply(true, DataHandler:RequestProgressReset(target))
	else
		return reply(false, "Unknown action.")
	end
	return reply(true, "Done.")
end

-- The public method is also the transport boundary, so Studio QA exercises the same validation.
function AdminHandler.Request(
	self: AdminHandler,
	actor: Player,
	action: any,
	targetId: any,
	amount: any,
	token: any
): Reply
	if not self:CanUse(actor) then
		return reply(false, "You do not have admin access.")
	end
	local now = os.clock()
	if busy[actor] or now - (lastRequest[actor] or -math.huge) < Config.RequestCooldown then
		return reply(false, "Too many requests. Wait a moment.")
	end
	lastRequest[actor] = now
	if
		typeof(action) ~= "string"
		or #action > 32
		or typeof(token) ~= "string"
		or #token > 64
		or typeof(targetId) ~= "number"
		or targetId ~= targetId
		or math.abs(targetId) == math.huge
		or targetId % 1 ~= 0
		or typeof(amount) ~= "number"
		or amount ~= amount
		or math.abs(amount) == math.huge
	then
		return reply(false, "Invalid request.")
	end
	if action == "audit" then
		return reply(
			true,
			if #audit > 0
				then table.concat(audit, "\n")
				else "No actions have been logged on this server yet."
		)
	end
	local target = Players:GetPlayerByUserId(targetId)
	if not target then
		return reply(
			false,
			"The player has left. Only players on this server are available."
		)
	end
	if action == "inspect" then
		return inspect(target)
	end
	local definition = Config.ById[action]
	if not definition then
		return reply(false, "Unknown action.")
	end
	if (action == "skipTutorial" or action == "resetTutorial") and not TutorialConfig.Enabled then
		return reply(
			false,
			"The tutorial is disabled in Configs/Tutorial.Enabled. Enable it to test tutorial actions."
		)
	end
	if definition.max then
		local minimum = if definition.allowZero then 0 else 1
		if amount % 1 ~= 0 or amount < minimum or amount > definition.max then
			return reply(false, `Enter a whole number between {minimum} and {definition.max}.`)
		end
	elseif amount ~= 0 then
		return reply(false, "This action does not accept an amount.")
	end
	local data = DataHandler:GetData(target)
	if not data or data.Cloud.ProgressResetPending then
		return reply(false, "The profile is not ready or has a pending reset.")
	end
	if token == "" then
		local issued = HttpService:GenerateGUID(false)
		pending[actor] = {
			token = issued,
			action = action,
			target = target,
			amount = amount,
			expires = now + Config.ConfirmationSeconds,
		}
		return {
			ok = true,
			token = issued,
			message = `{definition.label}\nPlayer: @{target.Name} ({target.UserId}){if definition.max
				then `\nAmount: {amount}`
				else ""}\n{definition.warning or "This change applies to the selected player."}\nConfirm within {Config.ConfirmationSeconds} seconds.`,
		}
	end
	local confirmation = pending[actor]
	pending[actor] = nil
	if
		not confirmation
		or confirmation.token ~= token
		or confirmation.action ~= action
		or confirmation.target ~= target
		or confirmation.amount ~= amount
		or confirmation.expires < now
	then
		return reply(
			false,
			"Confirmation expired or does not match. Select the action again."
		)
	end
	if targetBusy[target] then
		return reply(false, "Another request for this player is still running.")
	end
	busy[actor], targetBusy[target] = true, true
	local header =
		`{os.date("!%H:%M:%S")} UTC • {actor.Name} ({actor.UserId}) → {target.Name} ({target.UserId}) • {action} {amount}`
	Logger:Info(`Requested: {header}`)
	local ok, result = pcall(execute, action, target, amount)
	busy[actor], targetBusy[target] = nil, nil
	local response: Reply
	if ok then
		response = result
	else
		Logger:Warn(`Failed: {header}: {tostring(result)}`)
		response = reply(
			false,
			"The action failed. Check the player and server Output before retrying."
		)
	end
	local line = `{header} • {if response.ok then "OK" else "FAIL"} • {response.message}`
	Logger:Info(line)
	table.insert(audit, line)
	if #audit > 30 then
		table.remove(audit, 1)
	end
	response.message = `@{target.Name}: {response.message}`
	return response
end

function AdminHandler.OnStart(self: AdminHandler): ()
	local function setAccess(player: Player): ()
		player:SetAttribute("AdminPanelMockData", DataHandler.ForceMockData)
		player:SetAttribute(Config.AccessAttribute, self:CanUse(player))
	end
	Players.PlayerAdded:Connect(setAccess)
	for _, player in Players:GetPlayers() do
		setAccess(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player): ()
		lastRequest[player], pending[player], busy[player], targetBusy[player] = nil, nil, nil, nil
		for actor, confirmation in pending do
			if confirmation.target == player then
				pending[actor] = nil
			end
		end
	end)
	Bus.Admin.Request.OnServerInvoke = function(
		actor: Player,
		action: any,
		targetId: any,
		amount: any,
		token: any
	): Reply
		return self:Request(actor, action, targetId, amount, token)
	end
end

export type AdminHandler = typeof(AdminHandler)
return AdminHandler
