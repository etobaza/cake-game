--!strict
-- Owns one native invite attempt. Closing the prompt confirms no reward or delivered invitation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Invite = require(ReplicatedStorage.Shared.Configs.Friends).Invite

export type State = "Idle" | "Checking" | "Open"
export type Backend = {
	CanInvite: () -> boolean,
	Open: () -> (),
	IsStudio: () -> boolean,
}

local Prompt = {}
Prompt.__index = Prompt

export type Prompt = typeof(setmetatable(
	{} :: {
		Backend: Backend,
		Changed: (State) -> (),
		Toast: (string) -> (),
		Available: () -> boolean,
		State: State,
		Attempt: number,
		LastAttempt: number,
		Task: thread?,
		Timeout: thread?,
		Destroyed: boolean,
	},
	Prompt
))

function Prompt.new(backend: Backend, changed: (State) -> (), toast: (string) -> (), available: () -> boolean): Prompt
	return setmetatable({
		Backend = backend,
		Changed = changed,
		Toast = toast,
		Available = available,
		State = "Idle" :: State,
		Attempt = 0,
		LastAttempt = -math.huge,
		Task = nil,
		Timeout = nil,
		Destroyed = false,
	}, Prompt)
end

function Prompt.SetState(self: Prompt, state: State): ()
	self.State = state
	self.Changed(state)
end

function Prompt.ClearTimeout(self: Prompt): ()
	if self.Timeout then
		task.cancel(self.Timeout)
		self.Timeout = nil
	end
end

function Prompt.Finish(self: Prompt, message: string?): ()
	if self.Destroyed then
		return
	end
	-- Capability checks and native opening share one attempt and one owned worker.
	self.Attempt += 1
	self:ClearTimeout()
	local worker = self.Task
	self.Task = nil
	if worker and worker ~= coroutine.running() then
		task.cancel(worker)
	end
	self:SetState("Idle")
	if message and self.Available() then
		self.Toast(message)
	end
end

function Prompt.Request(self: Prompt): boolean
	local now = os.clock()
	if
		self.Destroyed
		or self.State ~= "Idle"
		or not self.Available()
		or now - self.LastAttempt < Invite.CooldownSeconds
	then
		return false
	end
	self.LastAttempt = now
	self.Attempt += 1
	local attempt = self.Attempt
	self:SetState("Checking")
	self.Timeout = task.delay(Invite.CheckTimeoutSeconds, function(): ()
		self.Timeout = nil
		self:Finish(if self.Backend.IsStudio() then Invite.StudioMessage else Invite.ErrorMessage)
	end)
	self.Task = task.defer(function(): ()
		local success, canInvite = pcall(self.Backend.CanInvite)
		if self.Destroyed or self.Attempt ~= attempt then
			return
		end
		self:ClearTimeout()
		if not self.Available() then
			self:Finish()
			return
		end
		if not success or canInvite ~= true then
			self:Finish(
				if self.Backend.IsStudio()
					then Invite.StudioMessage
					else (if success then Invite.UnavailableMessage else Invite.ErrorMessage)
			)
			return
		end
		-- Set Open before the native call so an immediate close event cannot be missed.
		self:SetState("Open")
		self.Timeout = task.delay(Invite.PromptTimeoutSeconds, function(): ()
			self.Timeout = nil
			self:Finish()
		end)
		local opened, errorMessage = pcall(function(): string?
			self.Backend.Open()
			return nil
		end)
		if self.Destroyed or self.Attempt ~= attempt then
			return
		end
		self.Task = nil
		if not opened then
			print(`[InviteHandler] Native invite prompt failed: {tostring(errorMessage)}`)
			self:Finish(if self.Backend.IsStudio() then Invite.StudioMessage else Invite.ErrorMessage)
		end
	end)
	return true
end

function Prompt.Closed(self: Prompt): ()
	if not self.Destroyed and self.State == "Open" then
		self:Finish()
	end
end

function Prompt.Destroy(self: Prompt): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Attempt += 1
	self:ClearTimeout()
	if self.Task then
		task.cancel(self.Task)
		self.Task = nil
	end
	self.State = "Idle"
end

return Prompt
