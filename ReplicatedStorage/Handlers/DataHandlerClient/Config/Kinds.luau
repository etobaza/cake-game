--!strict
--[[
	Canonical strings for the replicated data layer (server proxy + client cache).
	Wire format and Bus payloads use these same values.
]]

export type DataKind = "Cloud" | "Session"
export type SubscribeChannel = DataKind | "Any"
export type DataPath = { string | number }

return table.freeze({
	Cloud = "Cloud" :: DataKind,
	Session = "Session" :: DataKind,
	Any = "Any" :: SubscribeChannel,
})
