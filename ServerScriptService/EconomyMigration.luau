--!strict
-- One-time rescale of saved coin amounts, applied by DataHandler before PlayerReady.

--[[ Constants ]]--
-- Must match the CloudData template's EconomyVersion: new profiles already use this scale.
local VERSION = 1
-- Version 1 moved every coin amount to whole coins worth a hundredth of the old ones.
local COIN_SCALE = 100

--[[ Tables ]]--
local EconomyMigration = {}

--[[ Handling ]]--
--- `savedVersion` is read from the raw save before Reconcile adds the template's current version.
--- Writes go through the Cloud proxy; the version is saved with the balance, so a profile is only
--- ever rescaled once. Returns whether anything changed.
function EconomyMigration.Migrate(data: any, savedVersion: number): boolean
	if savedVersion >= VERSION then
		return false
	end

	local cloud = data.Cloud
	cloud.Cash = math.round(cloud.Cash * COIN_SCALE)
	cloud.EconomyVersion = VERSION
	return true
end

return EconomyMigration
