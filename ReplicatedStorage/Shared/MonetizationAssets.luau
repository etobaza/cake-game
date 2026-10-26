--!strict
-- Where the monetization models live: the worker accessories and the limited showcases and skins.
--
-- They sit in the Assets package (ReplicatedStorage.Assets.Models.Monetization), not in a place-only
-- folder, so every place of the experience gets them when the package updates. Code reaches the
-- folder only through here.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Tables ]]--
local MonetizationAssets = {
	-- Shown in warnings, so a missing template names the folder to look in.
	Path = "ReplicatedStorage.Assets.Models.Monetization",
}

--[[ Handling ]]--
--- The folder, or nil while the package does not hold it.
function MonetizationAssets.Get(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	return models and models:FindFirstChild("Monetization")
end

--- One template by name, or nil.
function MonetizationAssets.Find(name: string): Instance?
	local folder = MonetizationAssets.Get()
	return folder and folder:FindFirstChild(name)
end

return MonetizationAssets
