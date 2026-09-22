--!strict
-- Keeps unclaimed bakeries at the unupgraded appearance without losing authored variants.

local VacantView = {}

type PartState = {
	Part: BasePart,
	Transparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
	CanTouch: boolean,
	Vacant: boolean,
}

type EffectState = { Instance: Instance, Transparency: number?, Enabled: boolean?, Vacant: boolean }
export type Snapshot = { Parts: { PartState }, Effects: { EffectState } }

local function captureVariant(saved: Snapshot, variant: Instance): ()
	local vacant = variant.Name:match("^BuildPlaceholder%d*$") ~= nil
	local pieces = variant:GetDescendants()
	if variant:IsA("BasePart") then
		pieces[#pieces + 1] = variant
	end
	for _, piece in pieces do
		if piece:IsA("Decal") or piece:IsA("Texture") then
			saved.Effects[#saved.Effects + 1] = { Instance = piece, Transparency = piece.Transparency, Vacant = vacant }
		elseif
			piece:IsA("Light")
			or piece:IsA("Beam")
			or piece:IsA("Trail")
			or piece:IsA("ParticleEmitter")
			or piece:IsA("LayerCollector")
		then
			saved.Effects[#saved.Effects + 1] = { Instance = piece, Enabled = piece.Enabled, Vacant = vacant }
		end
		if not piece:IsA("BasePart") then
			continue
		end
		saved.Parts[#saved.Parts + 1] = {
			Part = piece,
			Transparency = piece.Transparency,
			CanCollide = piece.CanCollide,
			CanQuery = piece.CanQuery,
			CanTouch = piece.CanTouch,
			Vacant = vacant,
		}
	end
end

function VacantView.Capture(bakery: Folder): Snapshot
	local saved: Snapshot = { Parts = {}, Effects = {} }
	local floor = bakery:FindFirstChild("1ndFloor")
	if not floor then
		return saved
	end

	for _, zone in floor:GetChildren() do
		local upgrades = zone:FindFirstChild("Upgrades")
		if not upgrades then
			continue
		end
		for _, folder in upgrades:GetChildren() do
			-- Firewood is a starter supply even though the artist placed it under Upgrades.
			if zone.Name == "Kitchen" and folder.Name == "FireWood" then
				continue
			end
			for _, variant in folder:GetChildren() do
				captureVariant(saved, variant)
			end
		end
	end
	return saved
end

function VacantView.Apply(saved: Snapshot, occupied: boolean): ()
	for _, entry in saved.Parts do
		local part = entry.Part
		if not part.Parent then
			continue
		end
		local visible = occupied or entry.Vacant
		part.Transparency = if visible then entry.Transparency else 1
		part.CanCollide = visible and entry.CanCollide
		part.CanQuery = visible and entry.CanQuery
		part.CanTouch = visible and entry.CanTouch
	end
	for _, entry in saved.Effects do
		local effect = entry.Instance
		if not effect.Parent then
			continue
		end
		local visible = occupied or entry.Vacant
		if effect:IsA("Decal") then
			-- Texture derives from Decal, so one branch covers both.
			effect.Transparency = if visible then entry.Transparency :: number else 1
		elseif
			effect:IsA("Light")
			or effect:IsA("Beam")
			or effect:IsA("Trail")
			or effect:IsA("ParticleEmitter")
			or effect:IsA("LayerCollector")
		then
			-- Every class above has Enabled, but a property write needs a single class.
			local toggleable = effect :: any
			toggleable.Enabled = visible and entry.Enabled == true
		end
	end
end

return VacantView
