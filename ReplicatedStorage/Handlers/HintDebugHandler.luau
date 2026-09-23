--!strict
-- Cmdr preview owner. Real game systems use Shared/UI/Hint directly, without this handler.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bus = require(ReplicatedStorage.Shared.Bus)
local Config = require(ReplicatedStorage.Shared.Configs.Hint)
local Hint = require(ReplicatedStorage.Shared.UI.Hint)
local Interact = require(script.Parent.InteractHandler)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local UI = require(script.Parent.UIHandler)

local Handler = { dependencies = { "UIHandler", "InteractHandler" } }
local Owner = Janitor.new()
local Preview = Janitor.new()

local function guiTarget(path: string): GuiObject?
	local current: Instance? = UI.HudRoot
	if path == "-" then
		path = "Time"
	end
	if path:sub(1, 10) == "PlayerGui." then
		current = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		path = path:sub(11)
	end
	for _, name in string.split(path, ".") do
		current = current and current:FindFirstChild(name)
	end
	return if current and current:IsA("GuiObject") then current else nil
end

local function show(mode: string, path: string, duration: number, rotation: string): ()
	Preview:Cleanup()
	if mode == "hide" then
		return
	end
	local hint = Hint.new({ Priority = Config.DebugPriority, Duration = duration, Rotation = tonumber(rotation) })
	Preview:Add(hint, "Destroy")
	if mode == "gui" then
		if not guiTarget(path) then
			UI:Toast("Hint target not found: " .. path)
			Preview:Cleanup()
			return
		end
		hint:Gui(function()
			return guiTarget(path)
		end)
	elseif mode == "world" then
		local id = if path == "-" then "mixer_1" else path
		if not Interact:GetProp(id) then
			UI:Toast("Owned prop not found: " .. id)
			Preview:Cleanup()
			return
		end
		hint:World(function()
			return Interact:GetProp(id)
		end, { WorldOffset = Vector3.new(0, 1, 0) })
	else
		local started = os.clock()
		local character = Players.LocalPlayer.Character
		local root = character and character.PrimaryPart
		if not root then
			UI:Toast("Wait for your character to spawn.")
			Preview:Cleanup()
			return
		end
		local origin = root.Position
		-- A fixed ring in world space exercises all angles, behind-camera projection and player movement.
		hint:World(function(): Vector3
			local angle = (os.clock() - started) * 0.35
			return origin + Vector3.new(math.cos(angle) * 14, 2, math.sin(angle) * 14)
		end, { Occlusion = false })
	end
end

function Handler.OnStart(): ()
	Owner:Add(Preview, "Destroy")
	Owner:Add(Bus.Hints.Debug.OnClientEvent:Connect(show), "Disconnect")
end

function Handler.Destroy(): ()
	Owner:Destroy()
end

return Handler
