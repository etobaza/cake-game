--!strict
-- Shared desktop density. Apply geometry once; constraints under UIScale use rendered pixels.

local Theme = require(script.Parent.Theme)

local TextScale = {}

function TextScale.Get(viewport: Vector2): number
	local config = Theme.TextScale
	return math.clamp(
		math.min(viewport.X / config.ReferenceSize.X, viewport.Y / config.ReferenceSize.Y),
		config.Minimum,
		config.Maximum
	)
end

function TextScale.Fit(constraint: UITextSizeConstraint, scale: number): ()
	-- The baseline follows cloned rows and survives repeated compact/wide transitions.
	local authored = constraint:GetAttribute("AuthoredMaxTextSize")
	local maximum = if typeof(authored) == "number" then authored else constraint.MaxTextSize
	constraint:SetAttribute("AuthoredMaxTextSize", maximum)
	-- A large authored minimum must not overflow a page fitted to a short viewport.
	constraint.MinTextSize = 1
	constraint.MaxTextSize = math.max(1, math.floor(maximum * scale + 0.5))
end

return TextScale
