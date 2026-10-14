--!strict
-- Covers the join with the authored ReplicatedFirst.LoadingScreen: caches the game's art and sound
-- effects behind a real progress bar, then lifts once the character stands in its bakery.

--[[ Services ]]--
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--[[ References ]]--
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screen = ReplicatedFirst:WaitForChild("LoadingScreen") :: ScreenGui

screen.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local root = screen:WaitForChild("Root") :: CanvasGroup
local canvas = root:WaitForChild("Canvas") :: Frame
local fit = canvas:WaitForChild("Fit") :: UIScale
local cake = canvas:WaitForChild("Badge"):WaitForChild("Cake") :: ImageLabel
local bar = canvas:WaitForChild("Bar")
local fill = bar:WaitForChild("Track"):WaitForChild("Fill") :: Frame
local percent = bar:WaitForChild("Percent"):WaitForChild("Label")
local status = canvas:WaitForChild("Status"):WaitForChild("Label")
local tipText = canvas:WaitForChild("Tip"):WaitForChild("Text") :: TextLabel
local skip = canvas:WaitForChild("Skip") :: TextButton

-- The configs replicate after ReplicatedFirst; wait for them, then require them by path.
ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Loading")
ReplicatedStorage.Shared.Configs:WaitForChild("Sounds")

--[[ Modules ]]--
local LoadingConfig = require(ReplicatedStorage.Shared.Configs.Loading)
local SoundsConfig = require(ReplicatedStorage.Shared.Configs.Sounds)

--[[ Constants ]]--
-- Content properties that scripts can read, by exact class.
local CONTENT_PROPERTIES: { [string]: { string } } = {
	ImageLabel = { "Image" },
	ImageButton = { "Image", "HoverImage", "PressedImage" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	Sound = { "SoundId" },
	Animation = { "AnimationId" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
}
-- The canvas is drawn at this logical size and fitted uniformly to the screen.
local DESIGN = Vector2.new(canvas.Size.X.Offset, canvas.Size.Y.Offset)

--[[ Private Variables ]]--
local started = os.clock()
local target = 0
local shown = 0
local finished = false

--[[ Private Functions ]]--
-- Authored lettering is a black shadow copy under the white face; both carry the same text.
local function setLettering(holder: Instance, text: string): ()
	for _, label in holder:GetChildren() do
		if label:IsA("TextLabel") then
			label.Text = text
		end
	end
end

local function fitCanvas(): ()
	local size = screen.AbsoluteSize
	fit.Scale = math.min(size.X / DESIGN.X, size.Y / DESIGN.Y)
end

local function resolve(path: { string }): Instance?
	local current: Instance? = game:GetService(path[1] :: any)
	for index = 2, #path do
		current = current and current:FindFirstChild(path[index])
	end

	return current
end

-- Unique content ids, plus the instances whose content scripts cannot read (SurfaceAppearance).
local function collectContent(): { string | Instance }
	local items: { string | Instance } = {}
	local seen: { [string]: boolean } = {}
	local function add(content: unknown): ()
		if typeof(content) == "string" and content ~= "" and not seen[content] then
			seen[content] = true
			table.insert(items, content)
		end
	end

	for _, path in LoadingConfig.Preload do
		local source = resolve(path)
		if not source then
			print(`[Loading] Nothing to preload at {table.concat(path, ".")}`)
			continue
		end

		for _, instance in source:GetDescendants() do
			local properties = CONTENT_PROPERTIES[instance.ClassName]
			if properties then
				for _, property in properties do
					add((instance :: any)[property])
				end
			elseif instance:IsA("SurfaceAppearance") then
				table.insert(items, instance)
			end
		end
	end
	for _, sound in SoundsConfig.Sounds do
		if typeof(sound) == "table" then
			add(sound.Id)
		end
	end

	return items
end

local function preload(items: { string | Instance }): ()
	local batchSize = LoadingConfig.PreloadBatch
	for first = 1, #items, batchSize do
		if finished then
			return
		end

		local last = math.min(first + batchSize - 1, #items)
		ContentProvider:PreloadAsync(table.move(items, first, last, 1, {}))
		target = last / #items * LoadingConfig.AssetShare
	end
	target = LoadingConfig.AssetShare
end

local function cycleTips(): ()
	local tips = table.clone(LoadingConfig.Tips)
	local random = Random.new()
	local index = 0
	while not finished do
		index += 1
		if index > #tips then
			index = 1
		end
		-- Swap a random remaining tip forward, so every tip shows once before any repeats.
		local pick = random:NextInteger(index, #tips)
		tips[index], tips[pick] = tips[pick], tips[index]
		tipText.Text = tips[index]
		task.wait(LoadingConfig.TipSeconds)
	end
end

local function finish(): ()
	if finished then
		return
	end

	finished = true
	local fade = TweenService:Create(
		root,
		TweenInfo.new(LoadingConfig.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 1 }
	)
	fade.Completed:Once(function(): ()
		screen:Destroy()
	end)
	fade:Play()
end

--[[ Handling ]]--
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCanvas)
fitCanvas()
skip.Activated:Connect(finish)

local frame = RunService.RenderStepped:Connect(function(deltaTime: number): ()
	shown += (target - shown) * math.min(1, deltaTime * LoadingConfig.BarCatchUp)
	fill.Size = UDim2.fromScale(shown, 1)
	setLettering(percent, `{math.floor(shown * 100 + 0.5)}%`)

	local elapsed = os.clock() - started
	cake.Position = UDim2.new(0.5, 0, 0.5, math.sin(elapsed * LoadingConfig.BobSpeed) * LoadingConfig.BobPixels)
	cake.Rotation = math.sin(elapsed * LoadingConfig.SwaySpeed) * LoadingConfig.SwayDegrees
	skip.Visible = elapsed >= LoadingConfig.SkipAfterSeconds
end)
screen.Destroying:Once(function(): ()
	frame:Disconnect()
end)

task.spawn(cycleTips)

setLettering(status, LoadingConfig.Status.Assets)
if not game:IsLoaded() then
	game.Loaded:Wait()
end
preload(collectContent())

setLettering(status, LoadingConfig.Status.Bakery)
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
-- StarterGui reaches PlayerGui with the first character; the HUD binds from it.
playerGui:WaitForChild("MainGui")

local remaining = LoadingConfig.MinSeconds - (os.clock() - started)
if remaining > 0 then
	task.wait(remaining)
end
target = 1
task.wait(LoadingConfig.FullHoldSeconds)
finish()
