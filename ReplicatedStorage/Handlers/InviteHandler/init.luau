--!strict
-- Client-only native Roblox invitations; never sends reward claims to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Flux = require(ReplicatedStorage.Packages.flux)
local HudReveal = require(ReplicatedStorage.Shared.UI.Stores.HudReveal)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local UIHandler = require(ReplicatedStorage.Handlers.UIHandler)
local Control = require(script.Control)
local Prompt = require(script.Prompt)

local InviteHandler = {
	dependencies = { "UIHandler" },
}

function InviteHandler.OnStart(self: InviteHandler): ()
	self.Janitor = Janitor.new()
	local currency = UIHandler:GetHud("Currency") :: GuiObject
	local button, controlOwner = Control.Bind(currency, UIHandler.HudRoot)
	self.Button = button
	self.Janitor:Add(controlOwner, "Destroy")
	local function available(): boolean
		return Pages.Current:peek() == Pages.Names.None
			and not Pages.Presenting:peek()
			and HudReveal.Shown("Currency")
			and button:IsDescendantOf(game)
	end
	self.Prompt = Prompt.new({
		CanInvite = function(): boolean
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end,
		Open = function(): ()
			SocialService:PromptGameInvite(Players.LocalPlayer)
		end,
		IsStudio = function(): boolean
			return RunService:IsStudio()
		end,
	}, function(state: Prompt.State): ()
		button:SetAttribute("InviteState", state)
		button.Interactable = state == "Idle" and available()
	end, function(message: string): ()
		UIHandler:Toast(message)
	end, available)
	self.Janitor:Add(self.Prompt, "Destroy")
	button:SetAttribute("InviteState", "Idle")
	self.Janitor:Add(
		button.Activated:Connect(function(): ()
			self.Prompt:Request()
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		SocialService.GameInvitePromptClosed:Connect(function(player: Instance): ()
			if player == Players.LocalPlayer then
				self.Prompt:Closed()
			end
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		Scope.Run(function(): ()
			Flux(function(): ()
				local shown = Pages.Current() == Pages.Names.None
					and not Pages.Presenting()
					and HudReveal.Shown("Currency")
				button.Visible = shown
				button.Interactable = shown and self.Prompt.State == "Idle"
			end, true)
		end),
		"Destroy"
	)
end

function InviteHandler.Destroy(self: InviteHandler): ()
	self.Janitor:Cleanup()
end

export type InviteHandler = typeof(InviteHandler) & {
	Janitor: any,
	Button: TextButton,
	Prompt: Prompt.Prompt,
}

return InviteHandler :: InviteHandler
