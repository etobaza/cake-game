local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local _Bus = require(ReplicatedStorage.Shared.Bus)
local Cmdr = require(ReplicatedStorage.Packages.cmdr)
local Crystal = require(ReplicatedStorage.Shared.Crystal)

local cmdrRoot = ServerScriptService:FindFirstChild("Cmdr")
if cmdrRoot then
	local hooks = cmdrRoot:FindFirstChild("Hooks")
	local types = cmdrRoot:FindFirstChild("Types")
	local commands = cmdrRoot:FindFirstChild("Commands")

	if hooks then
		Cmdr:RegisterHooksIn(hooks)
	end
	if types then
		Cmdr:RegisterTypesIn(types)
	end
	if commands then
		Cmdr:RegisterCommandsIn(commands)
	end
end

local handlers = ServerScriptService:FindFirstChild("Handlers")
if handlers then
	for _, module in handlers:GetChildren() do
		if module:IsA("ModuleScript") then
			Crystal.Register(module)
		end
	end
end

Crystal.Run()
