--!strict
-- Local feedback sounds: opening/closing pages and items entering or leaving the hands.
-- Positional world sounds (oven fire, guests, cleaning) belong to their server owners.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local DataClient = require(script.Parent.DataHandlerClient)
local Flux = require(ReplicatedStorage.Packages.flux)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Pages = require(ReplicatedStorage.Shared.UI.Stores.Pages)
local Scope = require(ReplicatedStorage.Shared.UI.Scope)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)

--[[ Tables ]]--
local SoundHandler = {
	dependencies = { "DataClient" },
}

--[[ Private Functions ]]--
-- Count plus the newest item's identity; a replaced dispenser ingredient keeps the count but not the key.
local function handsKey(): (number, string)
	local hands = DataClient:GetData({ "Hands" }, "Session")
	if not hands then
		return 0, ""
	end
	local top = hands[#hands]
	return #hands, if top then `{top.Kind}:{top.Id}:{top.PickupAt or 0}` else ""
end

--[[ Handling ]]--
function SoundHandler.OnStart(self: SoundHandler): ()
	self.Janitor = Janitor.new()

	-- Switching between pages (e.g. the bakery menu tabs) is silent; opening from and closing to the HUD play.
	local page = Pages.Current:peek()
	self.Janitor:Add(
		Scope.Run(function(): ()
			Flux(function(): ()
				local current = Pages.Current()
				if current == page then
					return
				end
				if page == Pages.Names.None then
					SoundPlayer.Play("UiOpen")
				elseif current == Pages.Names.None then
					SoundPlayer.Play("UiClose")
				end
				page = current
			end, true)
		end),
		"Destroy"
	)

	DataClient:WaitForData()
	local count, key = handsKey()
	self.Janitor:Add(
		DataClient:SubscribeToPath({ "Hands" }, function(): ()
			local nextCount, nextKey = handsKey()
			if nextCount < count then
				SoundPlayer.Play("Put")
			elseif nextKey ~= key and nextKey ~= "" then
				SoundPlayer.Play("Get")
			end
			count, key = nextCount, nextKey
		end, "Session", true),
		"Disconnect"
	)
end

export type SoundHandler = typeof(SoundHandler) & {
	Janitor: any,
}

return SoundHandler :: SoundHandler
