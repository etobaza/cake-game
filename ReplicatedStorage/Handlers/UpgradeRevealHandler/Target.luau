--!strict
-- Resolves the exact purchase level, never another player's bakery or an asset template.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Base = require(Shared.Configs.Base)
local Buildings = require(Shared.Configs.Buildings)
local Config = require(Shared.Configs.UpgradeReveal)
local Garden = require(Shared.Configs.Garden)
local World = require(Shared.World)

local Target = {}
-- The eight corners of a unit box centred on the origin; scale by size / 2 for real bounds.
Target.Corners = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
} :: { Vector3 }
export type Target = { Bakery: Instance, Roots: { Instance }, Parts: { BasePart }, Frame: CFrame, Size: Vector3 }

function Target.Bakery(): Instance?
	local bakeries = World.Bakeries()
	if not bakeries then
		return nil
	end
	for _, bakery in bakeries:GetChildren() do
		if bakery:GetAttribute(Base.OwnerAttribute) == Players.LocalPlayer.UserId then
			return bakery
		end
	end
	return nil
end

local function resolve(root: Instance, path: string): Instance?
	return Buildings.ResolvePath(root, string.split(path, "."))
end

function Target.Roots(bakery: Instance, id: string, level: number): { Instance }
	local spec = Config.Targets[id]
	local roots: { Instance } = {}
	if not spec then
		return roots
	end
	if spec.Character then
		local character = Players.LocalPlayer.Character
		if character then
			table.insert(roots, character)
		end
		return roots
	end
	if spec.Source then
		local source = Garden.Sources[spec.Source]
		local folder = source and resolve(bakery, `1ndFloor.Garden.Upgrades.{source.Folder}`)
		if folder then
			for _, child in folder:GetChildren() do
				if child.Name:match("^Upgrade") then
					table.insert(roots, child)
				end
			end
		end
		return roots
	end
	local paths: { string } = spec.Paths or {}
	local path = spec.LevelPaths and spec.LevelPaths[level]
	if path then
		paths = { path }
	end
	for _, item in paths do
		local root = resolve(bakery, item)
		if root then
			table.insert(roots, root)
		end
	end
	return roots
end

function Target.Parts(roots: { Instance }): { BasePart }
	local parts: { BasePart } = {}
	for _, root in roots do
		if root:IsA("BasePart") then
			table.insert(parts, root)
		end
		for _, child in root:GetDescendants() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end
	return parts
end

function Target.Find(id: string, level: number): Target?
	local bakery = Target.Bakery()
	if not bakery then
		return nil
	end
	local roots = Target.Roots(bakery, id, level)
	local parts = Target.Parts(roots)
	local spec = Config.Targets[id]
	local focusParts = parts
	if spec and spec.FocusPaths then
		local focusRoots: { Instance } = {}
		for _, path in spec.FocusPaths do
			local root = resolve(bakery, path)
			if root then
				table.insert(focusRoots, root)
			end
		end
		if #focusRoots > 0 then
			focusParts = Target.Parts(focusRoots)
		end
	end
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	local count = 0
	for _, part in focusParts do
		-- Server visibility is authoritative. Local ambient copies can hide their stationary sources.
		if part.Transparency >= 1 or part.Name == "HumanoidRootPart" then
			continue
		end
		count += 1
		for _, corner in Target.Corners do
			local point = part.CFrame:PointToWorldSpace(part.Size * corner / 2)
			low = low:Min(point)
			high = high:Max(point)
		end
	end
	if count == 0 then
		return nil
	end
	if spec and spec.FocusHeight then
		high = Vector3.new(high.X, math.min(high.Y, low.Y + spec.FocusHeight), high.Z)
	end
	if spec and spec.FocusSize then
		local center = (low + high) / 2
		local halfSize = (high - low):Min(spec.FocusSize) / 2
		low = center - halfSize
		high = center + halfSize
	end
	local origin = Buildings.ResolvePath(bakery, Base.OriginPath)
	local rotation = if origin and origin:IsA("BasePart") then origin.CFrame.Rotation else CFrame.identity
	return {
		Bakery = bakery,
		Roots = roots,
		Parts = parts,
		Frame = CFrame.new((low + high) / 2) * rotation,
		Size = high - low,
	}
end

return Target
