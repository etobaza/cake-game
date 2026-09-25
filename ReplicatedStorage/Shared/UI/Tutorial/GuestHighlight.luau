--!strict
-- Client-owned outline for the incoming tutorial guest, resolved only inside the player's bakery.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Base = require(ReplicatedStorage.Shared.Configs.Base)
local Config = require(ReplicatedStorage.Shared.Configs.Tutorial)
local Guests = require(ReplicatedStorage.Shared.Configs.Guests)
local World = require(ReplicatedStorage.Shared.World)

--[[ Tables ]]--
local GuestHighlight = {}
GuestHighlight.__index = GuestHighlight

export type GuestHighlight = typeof(setmetatable(
	{} :: {
		UserId: number,
		Outline: Highlight?,
	},
	GuestHighlight
))

--[[ Private Functions ]]--
local function resolve(userId: number, guestId: string): Model?
	local bakeries = World.Bakeries()
	if not bakeries then
		return nil
	end

	for _, bakery in bakeries:GetChildren() do
		if bakery:GetAttribute(Base.OwnerAttribute) ~= userId then
			continue
		end

		local guests = bakery:FindFirstChild(Guests.FolderName)
		local guest = guests and guests:FindFirstChild(guestId)
		return if guest and guest:IsA("Model") then guest else nil
	end

	return nil
end

--[[ Handling ]]--
function GuestHighlight.new(userId: number): GuestHighlight
	return setmetatable({ UserId = userId }, GuestHighlight) :: GuestHighlight
end

function GuestHighlight.Clear(self: GuestHighlight): ()
	if self.Outline then
		self.Outline:Destroy()
		self.Outline = nil
	end
end

function GuestHighlight.Update(self: GuestHighlight, guestId: string?): ()
	local guest = if guestId then resolve(self.UserId, guestId) else nil
	if self.Outline and self.Outline.Parent == guest and self.Outline.Adornee == guest and guest then
		return
	end

	self:Clear()
	if not guest then
		return
	end

	local style = Config.GuestHighlight
	local outline = Instance.new("Highlight")
	outline.Name = "TutorialGuestHighlight"
	outline.Adornee = guest
	outline.DepthMode = style.DepthMode
	outline.FillColor = style.Color
	outline.FillTransparency = style.FillTransparency
	outline.OutlineColor = style.Color
	outline.OutlineTransparency = style.OutlineTransparency
	outline.Parent = guest
	self.Outline = outline
end

function GuestHighlight.Destroy(self: GuestHighlight): ()
	self:Clear()
end

return GuestHighlight
