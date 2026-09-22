local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _Bus = require(ReplicatedStorage.Shared.Bus)
local Crystal = require(ReplicatedStorage.Shared.Crystal)

-- Cmdr creates this module at runtime, so it is not part of the source tree.
local cmdrClient = ReplicatedStorage:FindFirstChild("CmdrClient")
if cmdrClient then
	require(cmdrClient :: ModuleScript)
end

local handlers = ReplicatedStorage:FindFirstChild("Handlers")
if handlers then
	for _, module in handlers:GetChildren() do
		if module:IsA("ModuleScript") then
			Crystal.Register(module)
		end
	end
end

Crystal.Run()
