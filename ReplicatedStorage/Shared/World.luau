--!strict
-- Locates the authored world. It ships as one Roblox package mounted at Workspace.World, so every
-- folder the code addresses by name lives one level below Workspace rather than directly in it.

--[[ Modules ]]--
local Base = require(script.Parent.Configs.Base)

--[[ Tables ]]--
local World = {}

--[[ Handling ]]--
function World.Root(): Instance?
	return workspace:FindFirstChild(Base.WorldFolderName)
end

--- Yields until the package exists in Workspace.
function World.WaitForRoot(): Instance
	return workspace:WaitForChild(Base.WorldFolderName)
end

function World.Bakeries(): Instance?
	local root = World.Root()
	return if root then root:FindFirstChild(Base.BakeriesFolderName) else nil
end

function World.WaitForBakeries(): Instance
	return World.WaitForRoot():WaitForChild(Base.BakeriesFolderName)
end

--- Walks a path of child names down from the package root; nil as soon as a name is missing.
function World.Find(path: { string }): Instance?
	local current = World.Root()
	for _, name in path do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

return World
