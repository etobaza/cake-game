--!strict
-- Limited items: one item on sale at a time for a fixed window (about a month), a fixed number of
-- copies shared by every server, each buyer numbered in order. Copies already bought stay owned for
-- good; when the window ends the next drop goes on sale and everyone can buy again.
--
-- Every drop is sold through the same developer product (Registries/Products `limited_slot`), so a
-- new drop needs no new Creator Dashboard product: add the item below and a Drops row. What owning an
-- item does is its own Products row (productType "limited"), read through Cloud.Passes like a pass.
-- LimitedHandler (server) owns the stock, serials and world changes; the client handler draws the
-- plaque and the prompt.

--[[ Types ]]--
export type Item = {
	-- Registries/Products entry (productType "limited") with the item's name and bonus.
	Entry: string,
	-- Copies of this item across all servers, ever.
	Stock: number,
	-- Model in ReplicatedStorage.MonetizationAssets cloned into every bakery while this item is
	-- the displayed drop.
	Showcase: string,
	-- Showcase pivot relative to each bakery's Entrance anchor. Every bakery authors its own
	-- Entrance, so this follows the rotated copies on the other side of the street.
	Placement: CFrame,
	-- Optional SurfaceAppearance in MonetizationAssets put on the owner's ovens, and where those
	-- ovens are: every Model named OvenModel under OvenRoot (the authored oven and both upgrades).
	OvenSurface: string?,
	OvenRoot: { string }?,
	OvenModel: string?,
}

-- One sale window. Times are fixed UTC Unix seconds so every server agrees; never derive them from
-- server start. Windows must not overlap; a gap between them shows the last drop as ended.
export type Drop = {
	Item: string,
	StartsAt: number,
	EndsAt: number,
}

--[[ Tables ]]--
local Limited = {
	-- Registries/Products entry of the one developer product every drop is sold through.
	SlotProduct = "limited_slot",

	Items = {
		golden_oven = {
			Entry = "limited_golden_oven",
			Stock = 5000,
			Showcase = "GoldenOvenShowcase",
			-- The kitchen wall beside the ovens, where the artist's plate shelf used to hang.
			Placement = CFrame.new(8.8, 3, 81.6) * CFrame.Angles(0, math.rad(180), 0),
			OvenSurface = "GoldenOvenSurface",
			OvenRoot = { "1ndFloor", "Kitchen" },
			OvenModel = "Oven",
		},
	} :: { [string]: Item },

	-- In start order.
	Drops = {
		-- 2026-10-21 00:00 UTC to 2026-11-21 00:00 UTC.
		{ Item = "golden_oven", StartsAt = 1792540800, EndsAt = 1795219200 },
	} :: { Drop },

	AssetsFolder = "MonetizationAssets",
	-- Workspace folder the showcases are cloned into; the authored world package stays untouched.
	ShowcaseFolder = "LimitedShowcases",
	-- Attributes on each showcase model. The server writes them, the client draws from them.
	ItemAttribute = "LimitedItem",
	BakeryAttribute = "Bakery",
	SoldAttribute = "Sold",
	StockAttribute = "Stock",
	EndsAtAttribute = "EndsAt",
	ActiveAttribute = "Active",

	-- Global counters: one key per item holding the number of copies sold. Studio sessions use their
	-- own store and topic so test purchases never move the live counter or reach live servers.
	StoreName = "LimitedStock",
	StudioStoreName = "LimitedStock_Studio",
	-- Cross-server "someone bought #N" message. Best effort; the periodic refresh fixes any miss.
	Topic = "LimitedSold",
	StudioTopic = "LimitedSold_Studio",
	-- How often servers re-read the counters and check whether the drop window changed.
	RefreshSeconds = 60,
	-- Serial assignment retries when the DataStore call fails; a rejoin retries again.
	SerialRetries = 3,
	SerialRetryDelay = 5,
	-- Per-player spacing between purchase requests.
	BuyCooldown = 2,
	-- After a prompt, further purchase requests wait this long for its receipt (a dismissed prompt
	-- frees the player at once).
	PendingSeconds = 30,

	-- Showcase presentation on the client.
	PromptDistance = 10,
	PromptAnchor = "Frame",
	PlaquePart = "PlaqueFace",
	RunePart = "Rune",
	OvenPart = "GoldenOven",
	-- Degrees per second for the rune, studs and seconds for the oven's float. Only showcases within
	-- AnimateDistance of the camera move.
	RuneSpeed = 12,
	BobHeight = 0.12,
	BobPeriod = 3,
	AnimateDistance = 90,
}

--[[ Handling ]]--
--- The drop on sale at `now`, if any.
function Limited.GetActiveDrop(now: number): Drop?
	for _, drop in Limited.Drops do
		if now >= drop.StartsAt and now < drop.EndsAt then
			return drop
		end
	end
	return nil
end

--- The drop the showcases display: the one on sale, otherwise the last one that has started (shown
--- as ended until the next window opens).
function Limited.GetDisplayedDrop(now: number): Drop?
	local latest: Drop? = nil
	for _, drop in Limited.Drops do
		if now >= drop.StartsAt and (latest == nil or drop.StartsAt > latest.StartsAt) then
			latest = drop
		end
	end
	return latest
end

return Limited
