--!strict
-- A local fade owns only local modifiers. Geometry, collision and server visibility stay untouched.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.UpgradeReveal)
local Ambient = require(ReplicatedStorage.Shared.Configs.AmbientMotion)
local Target = require(script.Parent.Target)

type Piece = BasePart | Decal
type Saved = { Modifier: number, Attribute: any, Ambient: boolean, Last: number }
local Appearance = {}
Appearance.__index = Appearance
export type Appearance = typeof(setmetatable({} :: { Saved: { [Piece]: Saved }, Alpha: number }, Appearance))

function Appearance.new(): Appearance
	return setmetatable({ Saved = {}, Alpha = 0 }, Appearance)
end

local function apply(piece: Piece, saved: Saved, alpha: number): ()
	if saved.Ambient then
		(piece :: Instance):SetAttribute(Config.AppearanceAttribute, alpha)
	else
		local modifier = saved.Modifier + (1 - saved.Modifier) * (1 - alpha)
		if piece:IsA("BasePart") then
			piece.LocalTransparencyModifier = modifier
		else
			(piece :: Decal).LocalTransparencyModifier = modifier
		end
		saved.Last = modifier
	end
end

function Appearance.Capture(self: Appearance, roots: { Instance }, hiddenOnly: boolean): ()
	for _, part in Target.Parts(roots) do
		if hiddenOnly and part.Transparency < 1 then
			continue
		end
		local pieces: { Piece } = { part }
		for _, child in part:GetDescendants() do
			if child:IsA("Decal") and not part:HasTag(Ambient.Tag) then
				table.insert(pieces, child)
			end
		end
		for _, piece in pieces do
			if self.Saved[piece] then
				continue
			end
			local saved = {
				Modifier = piece.LocalTransparencyModifier,
				Attribute = piece:GetAttribute(Config.AppearanceAttribute),
				Ambient = piece:IsA("BasePart") and piece:HasTag(Ambient.Tag),
				Last = piece.LocalTransparencyModifier,
			}
			self.Saved[piece] = saved
			apply(piece, saved, self.Alpha)
		end
	end
end

function Appearance.Set(self: Appearance, alpha: number): ()
	self.Alpha = math.clamp(alpha, 0, 1)
	for piece, saved in self.Saved do
		if piece.Parent then
			apply(piece, saved, self.Alpha)
		end
	end
end

function Appearance.Destroy(self: Appearance): ()
	for piece, saved in self.Saved do
		if not piece.Parent then
			continue
		end
		if saved.Ambient then
			(piece :: Instance):SetAttribute(Config.AppearanceAttribute, saved.Attribute)
		elseif math.abs(piece.LocalTransparencyModifier - saved.Last) < 1e-4 then
			-- A newer visibility owner is allowed to retain its value.
			if piece:IsA("BasePart") then
				piece.LocalTransparencyModifier = saved.Modifier
			else
				(piece :: Decal).LocalTransparencyModifier = saved.Modifier
			end
		end
	end
	table.clear(self.Saved)
end

return Appearance
