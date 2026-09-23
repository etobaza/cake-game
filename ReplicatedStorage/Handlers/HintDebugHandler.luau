--!strict
-- Cmdr preview owner. Real game systems use Shared/UI/Hint directly, without this handler.

--[[ Services ]]
--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]
--
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Hint = require(ReplicatedStorage.Shared.UI.Hint)
local Interact = require(script.Parent.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local UI = require(script.Parent.UIHandler)

--[[ Constants ]]
--
local PLAYER_GUI_PREFIX = "PlayerGui."

--[[ Tables ]]
--
local Handler = { dependencies = { "UIHandler", "InteractHandler" } }
local Owner = Janitor.new()
local Preview = Janitor.new()

--[[ Private Functions ]]
--
local function guiTarget(path: string): GuiObject?
	local current: Instance? = UI.HudRoot
	if path == "-" then
		path = Config.Debug.GuiPath
	end

	if path:sub(1, #PLAYER_GUI_PREFIX) == PLAYER_GUI_PREFIX then
		current = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		path = path:sub(#PLAYER_GUI_PREFIX + 1)
	end

	for _, name in string.split(path, ".") do
		current = current and current:FindFirstChild(name)
	end

	return if current and current:IsA("GuiObject") then current else nil
end

local function showGui(hint: Hint.View, path: string): boolean
	if not guiTarget(path) then
		UI:Toast("Hint target not found: " .. path)
		return false
	end

	hint:Gui(function(): GuiObject?
		return guiTarget(path)
	end)

	return true
end

local function showWorld(hint: Hint.View, path: string): boolean
	local id = if path == "-" then Config.Debug.PropId else path
	if not Interact:GetProp(id) then
		UI:Toast("Owned prop not found: " .. id)
		return false
	end

	hint:World(function(): BasePart?
		return Interact:GetProp(id)
	end, { WorldOffset = Config.Debug.WorldOffset })

	return true
end

local function showDemo(hint: Hint.View, _path: string): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character.PrimaryPart
	if not root then
		UI:Toast("Wait for your character to spawn.")
		return false
	end

	local started = os.clock()
	local origin = root.Position

	-- A fixed ring exercises camera turns and behind-camera projection.
	hint:World(function(): Vector3
		local angle = (os.clock() - started) * Config.Debug.DemoAngularSpeed
		return origin
			+ Vector3.new(
				math.cos(angle) * Config.Debug.DemoRadius,
				Config.Debug.DemoHeight,
				math.sin(angle) * Config.Debug.DemoRadius
			)
	end, { Occlusion = false })

	return true
end

local Presenters: { [string]: (Hint.View, string) -> boolean } = {
	gui = showGui,
	world = showWorld,
	demo = showDemo,
}

local function show(mode: string, path: string, duration: number, rotation: string): ()
	Preview:Cleanup()

	local present = Presenters[mode]
	if not present then
		return
	end

	local hint = Hint.new({ Priority = Config.DebugPriority, Duration = duration, Rotation = tonumber(rotation) })
	Preview:Add(hint, "Destroy")

	if not present(hint, path) then
		Preview:Cleanup()
	end
end

--[[ Handling ]]
--
function Handler.OnStart(): ()
	Owner:Add(Preview, "Destroy")
	Owner:Add(Bus.Hints.Debug.OnClientEvent:Connect(show), "Disconnect")
end

function Handler.Destroy(): ()
	Owner:Destroy()
end

return Handler
