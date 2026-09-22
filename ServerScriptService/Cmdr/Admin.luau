--!strict
-- Who may run Admin-group console commands. Lives under ServerScriptService, not in the shared
-- registries: ReplicatedStorage replicates to every client, and this list is a target list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage.Shared.Registry)

export type AdminEntry = {
	userId: number,
	username: string,
	role: string,
} & { id: string }

local list = {
	-- Add admin UserIds here
	codebykoi = {
		userId = 173950796,
		username = "codebykoi",
		role = "developer",
	},
	funseti = {
		userId = 11124027070,
		username = "funseti",
		role = "developer",
	},
} :: { [string]: AdminEntry }

local methods = {
	IsAdmin = function(self: AdminRegistry, userId: number): boolean
		return self:Query():Any(function(e: AdminEntry)
			return e.userId == userId
		end)
	end,

	GetAdmin = function(self: AdminRegistry, userId: number): AdminEntry?
		return self:Query()
			:Where(function(e: AdminEntry)
				return e.userId == userId
			end)
			:FirstOrDefault()
	end,

	GetAdmins = function(self: AdminRegistry): { AdminEntry }
		return self:Query():ToArray()
	end,
}

local AdminRegistry = Registry.Build("Admin", list, methods)
export type AdminRegistry = typeof(AdminRegistry)

return AdminRegistry
