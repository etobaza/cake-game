--!strict
-- Which full-screen page is open. One page at a time: opening a second closes the first, so no screen
-- has to know about any other. Panels read IsOpen and nothing else.
--
-- The HUD is not a page -- it is always up. Pages are the things that cover it.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)

--[[ Types ]]--
export type Page = string

--[[ Tables ]]--
local Pages = {}

-- Pages with a system behind them. Inventory plans the next day's menu and RecipeToCook is the station pick;
-- both are named after the screen they were drawn as.
Pages.Names = {
	None = "None",
	Codes = "Codes",
	DailyRewards = "DailyRewards",
	Inventory = "Inventory",
	Playtime = "Playtime",
	RecipeToCook = "RecipeToCook",
	Report = "Report",
	Store = "Store",
	Upgrades = "Upgrades",
} :: { [string]: Page }

-- Screens whose layout is ported but which have no system behind them yet. They open and close; the
-- content inside is a mock until the feature is built. Empty at the moment -- every drawn screen has
-- something behind it.
Pages.Planned = {} :: { [string]: Page }

--[[ Private Variables ]]--
local current = Flux(Pages.Names.None)
local previous = Flux(Pages.Names.None)
-- The evening modal allows its report/menu tabs while preventing dismissal.
local locked = Flux(false)
local allowedWhileLocked: { [Page]: boolean } = {}

--[[ Public nodes ]]--
Pages.Current = current
Pages.Previous = previous
Pages.Locked = locked

--[[ Handling ]]--
--- A node that is true exactly while `page` is the open one. Bind it to Enabled or Visible.
function Pages.IsOpen(page: Page): Flux.Node<boolean>
	return Flux.computed(function(): boolean
		return current() == page
	end)
end

--- Reactive permission check shared by routing and navigation affordances.
function Pages.CanOpen(page: Page): boolean
	return not locked() or allowedWhileLocked[page] == true
end

--- Opens `page`, closing whatever was open. A lock may allow specific pages.
function Pages.Open(page: Page): boolean
	if not Pages.CanOpen(page) then
		return false
	end
	if current:peek() == page then
		return true
	end

	previous:set(current:peek())
	current:set(page)
	return true
end

--- Closes whatever is open. Refused while locked.
function Pages.Close(): boolean
	return Pages.Open(Pages.Names.None)
end

--- Opens `page`, or closes it if it is already the open one.
function Pages.Toggle(page: Page): boolean
	if current:peek() == page then
		return Pages.Close()
	end
	return Pages.Open(page)
end

--- Without an allowlist, a lock blocks every transition. Evening tabs share one allowlist.
function Pages.SetLocked(isLocked: boolean, allowedPages: { [Page]: boolean }?): ()
	allowedWhileLocked = allowedPages or {}
	-- An updated allowlist must refresh navigation even when the lock stays enabled.
	locked:set(isLocked, true)
end

return Pages
