--!strict
-- Client texture copies preserve the authored UVs. The server owns the burn fraction.
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Configs.FoodBurn)
local FoodTextures = require(ReplicatedStorage.Shared.Configs.FoodTextures)
local FoodBurn = require(ReplicatedStorage.Shared.FoodBurn)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Logger = require(ReplicatedStorage.Shared.Libs.Logger).new({ name = "FoodBurnHandler" })
local Texture = require(script.Texture)

type Entry = {
	Part: BasePart,
	Alive: boolean,
	Loading: boolean,
	Failed: boolean,
	Original: SurfaceAppearance?,
	Material: SurfaceAppearance?,
	Image: EditableImage?,
	Palette: Texture.Palette?,
	Tint: Color3?,
	Fade: number,
	Updated: number,
}

local FoodBurnHandler = {}

local function applyTint(source: SurfaceAppearance, original: Color3, fade: number): ()
	local tint = FoodBurn.Color(Color3.new(0.5, 0.5, 0.5), fade)
	source.Color = Color3.new(original.R * tint.R * 2, original.G * tint.G * 2, original.B * tint.B * 2)
end

local function frameBudget(): () -> ()
	local started = os.clock()
	return function()
		if os.clock() - started >= Config.WorkBudgetSeconds then
			RunService.Heartbeat:Wait()
			started = os.clock()
		end
	end
end

local function destroy(entry: Entry): ()
	entry.Alive = false
	if entry.Material then
		entry.Material:Destroy()
		entry.Material = nil
	end
	if entry.Image then
		entry.Image:Destroy()
		entry.Image = nil
	end
	if entry.Original then
		if entry.Part.Parent then
			entry.Original.Color = entry.Tint or Color3.new(1, 1, 1)
			entry.Original.Parent = entry.Part
		else
			entry.Original:Destroy()
		end
	end
end

function FoodBurnHandler.Prepare(self: FoodBurnHandler, entry: Entry, source: SurfaceAppearance): ()
	self.Busy = true
	entry.Loading = true
	entry.Original = source
	entry.Tint = entry.Tint or source.Color
	-- Async asset reads may finish after removal; every returned object checks this entry's lifetime.
	task.spawn(function()
		local yieldWork = frameBudget()
		local ok, message = pcall(function(): boolean
			local key = if entry.Part:IsA("MeshPart") then FoodTextures[entry.Part.MeshId] else nil
			assert(key, `No authored food color map for {entry.Part.Name}`)
			local palette = self.Palettes[key]
			if not palette then
				palette = Texture.Read(Content.fromUri(key), yieldWork)
				if not entry.Alive then
					return true
				end
				self.Palettes[key] = palette
			end
			if not entry.Alive then
				return true
			end
			local image = AssetService:CreateEditableImage({ Size = palette.Size })
			assert(image, "No editable-image memory for the burning dish")
			entry.Image, entry.Palette = image, palette
			image:WritePixelsBuffer(Vector2.zero, palette.Size, Texture.Render(palette, 0))
			-- MASTER_FoodFade is an unlit color shader; this copy carries its color result.
			-- Original PBR maps stay on the retained authored appearance for restoration.
			local material = AssetService:CreateSurfaceAppearanceAsync({ ColorMap = Content.fromObject(image) })
			if not entry.Alive then
				material:Destroy()
				return true
			end
			material.Color = entry.Tint or source.Color
			material.AlphaMode = source.AlphaMode
			entry.Material = material
			-- Keep the authored material visible until the first correctly colored copy is ready.
			return true
		end)
		entry.Loading = false
		self.Busy = false
		if not ok and entry.Alive then
			entry.Failed = true
			if entry.Image then
				entry.Image:Destroy()
				entry.Image = nil
			end
			Logger:Warn(`Food color texture unavailable; using tint fallback: {message}`)
		end
	end)
end

function FoodBurnHandler.Track(self: FoodBurnHandler, instance: Instance): ()
	if not instance:IsA("BasePart") or self.Entries[instance] then
		return
	end
	local viewport = instance:FindFirstAncestorWhichIsA("ViewportFrame")
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local isPreview = viewport ~= nil and playerGui ~= nil and viewport:IsDescendantOf(playerGui)
	if not instance:IsDescendantOf(workspace) and not isPreview then
		return
	end
	local entry: Entry = {
		Part = instance,
		Alive = true,
		Loading = false,
		Failed = false,
		Fade = -1,
		Updated = 0,
	}
	self.Entries[instance] = entry
	-- A completed burnt preview must not flash fresh while its exact texture loads.
	local source = instance:FindFirstChildWhichIsA("SurfaceAppearance")
	local fade = instance:GetAttribute(Config.FadeAttribute)
	if isPreview and source and typeof(fade) == "number" and fade > 0 then
		entry.Original, entry.Tint = source, source.Color
		applyTint(source, source.Color, math.clamp(fade, 0, 1))
	end
end

function FoodBurnHandler.Untrack(self: FoodBurnHandler, instance: Instance): ()
	local entry = self.Entries[instance]
	if entry then
		destroy(entry)
		self.Entries[instance] = nil
	end
end

function FoodBurnHandler.Update(self: FoodBurnHandler): ()
	if self.Busy then
		return
	end
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local chosen: Entry? = nil
	local target = 0
	for _, entry in self.Entries do
		if
			camera
			and not entry.Part:FindFirstAncestorWhichIsA("ViewportFrame")
			and (entry.Part.Position - camera.CFrame.Position).Magnitude > Config.RenderDistance
		then
			continue
		end
		local fade = entry.Part:GetAttribute(Config.FadeAttribute)
		if typeof(fade) ~= "number" or entry.Loading or now - entry.Updated < Config.RefreshSeconds then
			continue
		end
		fade = math.clamp(fade, 0, 1)
		if fade == entry.Fade or (fade == 0 and not entry.Material) then
			continue
		end
		if not chosen or entry.Updated < chosen.Updated then
			chosen, target = entry, fade
		end
	end
	if not chosen then
		return
	end
	local entry = chosen
	entry.Updated = now
	local source = entry.Original or entry.Part:FindFirstChildWhichIsA("SurfaceAppearance")
	if not source then
		return
	end
	if entry.Failed then
		applyTint(source, entry.Tint or Color3.new(1, 1, 1), target)
		entry.Fade = target
	elseif entry.Image and entry.Palette and entry.Material then
		local image, palette, material = entry.Image, entry.Palette, entry.Material
		self.Busy = true
		task.spawn(function()
			local pixels = Texture.Render(palette, target, frameBudget())
			if entry.Alive then
				image:WritePixelsBuffer(Vector2.zero, palette.Size, pixels)
				source.Parent = nil
				material.Parent = entry.Part
				entry.Fade = target
			end
			self.Busy = false
		end)
	else
		self:Prepare(entry, source)
	end
end

function FoodBurnHandler.OnInit(self: FoodBurnHandler): ()
	self.Janitor = Janitor.new()
	self.Entries = {}
	self.Palettes = {}
	self.Busy = false
end

function FoodBurnHandler.OnStart(self: FoodBurnHandler): ()
	self.Janitor:Add(
		CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(function(instance: Instance)
			self:Track(instance)
		end),
		"Disconnect"
	)
	self.Janitor:Add(
		CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(instance: Instance)
			self:Untrack(instance)
		end),
		"Disconnect"
	)
	for _, instance in CollectionService:GetTagged(Config.Tag) do
		self:Track(instance)
	end
	self.Janitor:Add(
		RunService.Heartbeat:Connect(function()
			-- At most one texture upload per frame; completed/paused fractions generate no work.
			self:Update()
		end),
		"Disconnect"
	)
end

function FoodBurnHandler.Destroy(self: FoodBurnHandler): ()
	self.Janitor:Destroy()
	for _, entry in self.Entries do
		destroy(entry)
	end
	table.clear(self.Entries)
	table.clear(self.Palettes)
end

export type FoodBurnHandler = typeof(FoodBurnHandler) & {
	Janitor: any,
	Entries: { [Instance]: Entry },
	Palettes: { [string]: Texture.Palette },
	Busy: boolean,
}

return FoodBurnHandler :: FoodBurnHandler
