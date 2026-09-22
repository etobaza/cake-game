--!strict
-- A generated developer overlay; authored gameplay screens continue to belong to UIHandler.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Configs.Admin)
local Bus = require(ReplicatedStorage.Shared.Bus)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local View = require(script.View)

type Pending = { action: string, targetId: number, amount: number, token: string }
local player = Players.LocalPlayer

local AdminPanelHandler = { priority = -20 }

function AdminPanelHandler.OnStart(_self: AdminPanelHandler): ()
	local lifetime = Janitor.new()
	local viewOwner = Janitor.new()
	lifetime:Add(viewOwner, "Destroy")
	local view: View.View? = nil
	local selected = player.UserId
	local pending: Pending? = nil
	local busy = false
	local generation = 0
	local nextRequestAt = 0
	local roster: { Player } = {}

	local function cancel(): ()
		pending = nil
		if view then
			view.Confirm.Visible = false
			view.Actions.Visible = true
		end
	end

	local function refreshRoster(): ()
		roster = Players:GetPlayers()
		table.sort(roster, function(a: Player, b: Player): boolean
			return a.Name:lower() < b.Name:lower()
		end)
		if not Players:GetPlayerByUserId(selected) then
			selected = player.UserId
			cancel()
		end
		local target = Players:GetPlayerByUserId(selected)
		if view and target then
			view.Target.Text = `{target.DisplayName} • @{target.Name} • {target.UserId}`
		end
	end

	local function request(action: string, targetId: number, amount: number, token: string): ()
		local currentView = view
		if busy or not currentView then
			return
		end
		busy = true
		local version = generation
		currentView.Result.Text = "Waiting for server…"
		task.spawn(function(): ()
			local delaySeconds = nextRequestAt - os.clock()
			if delaySeconds > 0 then
				task.wait(delaySeconds)
			end
			if version ~= generation then
				return
			end
			nextRequestAt = os.clock() + Config.RequestCooldown + 0.1
			local ok, response = pcall(function(): any
				return Bus.Admin.Request:Fire(action, targetId, amount, token)
			end)
			if version ~= generation then
				return
			end
			busy = false
			if not ok or typeof(response) ~= "table" or typeof(response.message) ~= "string" then
				cancel()
				currentView.Result.Text =
					"No server response. Check the player before retrying: the action may already have completed."
				return
			end
			currentView.Result.Text = response.message
			currentView.Result.TextColor3 = if response.ok
				then Color3.fromRGB(219, 233, 224)
				else Color3.fromRGB(255, 149, 149)
			currentView.ResultScroll.CanvasPosition = Vector2.zero
			if typeof(response.token) == "string" and selected == targetId and currentView.Panel.Visible then
				pending = { action = action, targetId = targetId, amount = amount, token = response.token }
				currentView.ConfirmText.Text = response.message
				currentView.Confirm.Visible = true
				currentView.Actions.Visible = false
			else
				cancel()
			end
		end)
	end

	local function toggle(): ()
		if view then
			view.Panel.Visible = not view.Panel.Visible
			cancel()
			if view.Panel.Visible then
				refreshRoster()
				request("inspect", selected, 0, "")
			end
		end
	end

	local function mount(): ()
		generation += 1
		viewOwner:Cleanup()
		view, pending, busy = nil, nil, false
		if player:GetAttribute(Config.AccessAttribute) ~= true then
			return
		end
		local created = View.Create(player:WaitForChild("PlayerGui") :: PlayerGui, viewOwner)
		view = created
		refreshRoster()
		viewOwner:Add(created.Toggle.Activated:Connect(toggle))
		viewOwner:Add(created.Close.Activated:Connect(toggle))
		viewOwner:Add(created.Cancel.Activated:Connect(cancel))
		viewOwner:Add(created.Accept.Activated:Connect(function(): ()
			if busy then
				return
			end
			local confirmation = pending
			if confirmation then
				cancel()
				request(confirmation.action, confirmation.targetId, confirmation.amount, confirmation.token)
			end
		end))
		for direction, button in { [-1] = created.Previous, [1] = created.Next } do
			viewOwner:Add(button.Activated:Connect(function(): ()
				if busy or #roster == 0 then
					return
				end
				local index = 1
				for i, entry in roster do
					if entry.UserId == selected then
						index = i
						break
					end
				end
				selected = roster[(index - 1 + direction) % #roster + 1].UserId
				cancel()
				refreshRoster()
				request("inspect", selected, 0, "")
			end))
		end
		for action, button in created.Buttons do
			viewOwner:Add(button.Activated:Connect(function(): ()
				if busy then
					return
				end
				local definition = Config.ById[action]
				local amount = if definition and definition.max then tonumber(created.Amount.Text) else 0
				if not amount then
					created.Result.Text = "Enter a numeric amount."
					return
				end
				cancel()
				request(action, selected, amount, "")
			end))
		end
		local command = Instance.new("TextChatCommand")
		command.Name = "AdminPanelCommand"
		command.PrimaryAlias = "/admin"
		command.Parent = TextChatService
		viewOwner:Add(command)
		viewOwner:Add(command.Triggered:Connect(toggle))
	end

	lifetime:Add(player:GetAttributeChangedSignal(Config.AccessAttribute):Connect(mount))
	lifetime:Add(Players.PlayerAdded:Connect(refreshRoster))
	lifetime:Add(Players.PlayerRemoving:Connect(function(leaving: Player): ()
		if leaving.UserId == selected then
			selected = player.UserId
			cancel()
		end
		task.defer(refreshRoster)
	end))
	lifetime:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean): ()
		if not processed and not UserInputService:GetFocusedTextBox() and input.KeyCode == Enum.KeyCode.F4 then
			toggle()
		end
	end))
	lifetime:Add(script.Destroying:Connect(function(): ()
		generation += 1
		lifetime:Destroy()
	end))
	mount()
end

export type AdminPanelHandler = typeof(AdminPanelHandler)
return AdminPanelHandler
