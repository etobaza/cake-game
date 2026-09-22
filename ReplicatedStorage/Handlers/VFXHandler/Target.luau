--!strict
-- An event-bound food or guest attachment. Streaming removal drains its visual immediately.
--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Config = require(ReplicatedStorage.Shared.Configs.VFX)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Effect = require(script.Parent.Effect)

--[[ Tables ]]--
local Target = {}
Target.__index = Target
export type Target = typeof(setmetatable(
	{} :: {
		Part: BasePart,
		Root: Folder,
		Templates: { [string]: BasePart },
		Janitor: any,
		Visual: Effect.Effect?,
		Offset: CFrame,
		Active: boolean,
		Repeats: boolean,
		NextAt: number,
	},
	Target
))

--[[ Private Functions ]]--
local function scaledFrame(frame: CFrame, factor: number): CFrame
	return CFrame.new(frame.Position * factor) * frame.Rotation
end

--[[ Handling ]]--
function Target.new(part: BasePart, root: Folder, templates: { [string]: BasePart }): Target
	local self: Target = setmetatable({
		Part = part,
		Root = root,
		Templates = templates,
		Janitor = Janitor.new(),
		Offset = CFrame.identity,
		Active = false,
		Repeats = false,
		NextAt = 0,
	}, Target)
	self.Janitor:Add(
		part.AttributeChanged:Connect(function(): ()
			self:Refresh()
		end),
		"Disconnect"
	)
	self:Refresh()
	return self
end

function Target.Refresh(self: Target): ()
	local role = self.Part:GetAttribute(Config.RoleAttribute)
	if role == "Guest" then
		self.Active = self.Part:GetAttribute(Config.ChoosingAttribute) == true
		self.Repeats = true
		return
	end
	self.Active = role == "Food"
	if not self.Active or self.Visual then
		return
	end
	local recipe = self.Part:GetAttribute("RecipeId")
	local preset = if typeof(recipe) == "string" then Config.FoodPresets[recipe] else nil
	local template = preset and self.Templates[preset]
	local size = self.Part:GetAttribute(Config.SizeAttribute)
	local offset = self.Part:GetAttribute(Config.OffsetAttribute)
	local sourceSize = template and template:GetAttribute("SourceFoodSize")
	if not template or typeof(size) ~= "Vector3" or typeof(offset) ~= "CFrame" or typeof(sourceSize) ~= "Vector3" then
		return
	end
	local scale = math.clamp(
		math.max(size.X, size.Z) / math.max(sourceSize.X, sourceSize.Z, 0.01),
		Config.MinFoodScale,
		Config.MaxFoodScale
	)
	local sourceOffset = template:GetAttribute("SourceOffset")
	self.Offset = offset
		* scaledFrame(if typeof(sourceOffset) == "CFrame" then sourceOffset else CFrame.identity, scale)
	self.Visual = Effect.new(template, self.Root, scale)
	self.Janitor:Add(self.Visual, "Destroy", "Visual")
end

function Target.Step(self: Target, now: number, camera: Vector3): ()
	local near = (self.Part.Position - camera).Magnitude <= Config.Distance
	local active = self.Active and near and self.Part:IsDescendantOf(workspace)
	if active and self.Repeats and not self.Visual then
		local template = self.Templates.SpeakingIdle
		if not template then
			return
		end
		self.Visual = Effect.new(template, self.Root)
		self.Janitor:Add(self.Visual, "Destroy", "Visual")
	end
	local visual = self.Visual
	if not visual then
		return
	end
	if self.Repeats then
		if active and now >= self.NextAt then
			visual:Burst(now)
			self.NextAt = now + Config.SpeakingInterval
		elseif not active then
			visual:Cancel(now)
			self.NextAt = 0
		end
	else
		visual:SetEnabled(active, now)
	end
	visual:Step(self.Part.CFrame * self.Offset, now)
end

function Target.Destroy(self: Target): ()
	self.Janitor:Destroy()
end

return Target
