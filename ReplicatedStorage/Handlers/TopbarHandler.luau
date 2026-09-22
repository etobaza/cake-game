--!strict
-- The topbar: Daily Rewards and Codes, as TopbarPlus icons sitting beside Roblox's own buttons.
--
-- Daily Rewards and Codes used to be the `CoreBtns` strip drawn into the HUD. TopbarPlus owns that
-- row now, so the icons are created here rather than authored in StarterGui: they are not part of
-- any screen and there is no layout to draw for them. Playtime rewards moved off the topbar onto
-- the HUD's own Rewards button (SideBtns, see Shared/UI/Components/Hud).
--
-- The icons never decide anything: a click asks Stores/Pages to toggle, and the selected state
-- follows what the store ended up doing. A page closed by its own X, by another page opening, or
-- refused because the tutorial locked the store, all leave the icon showing the truth.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Packages = ReplicatedStorage.Packages

--[[ Modules ]]--
local Flux = require(_Packages.flux)
local Janitor = require(_Packages.janitor)
local Pages = require(_Shared.UI.Stores.Pages)
local Scope = require(_Shared.UI.Scope)
local TopbarIcon = require(_Packages["topbar-plus"])

--[[ Constants ]]--
-- One row per icon: the page it toggles, the art it wears, its hover caption and where it sits in
-- the row. The images are the ones the old CoreBtns strip used, so the topbar reads as what it
-- replaced.
local ICONS: { { Page: string, Image: string, Caption: string, Order: number } } = {
	{
		Page = Pages.Names.DailyRewards,
		Image = "rbxassetid://85783457068970",
		Caption = "Daily Rewards",
		Order = 1,
	},
	{
		Page = Pages.Names.Codes,
		Image = "rbxassetid://109386928213191",
		Caption = "Codes",
		Order = 2,
	},
}

--[[ Private Functions ]]--
-- TopbarPlus exports its Icon type as methods only -- the runtime fields are commented out of it
-- upstream -- so the selected flag is read through a cast rather than off the typed surface.
local function isSelected(icon: TopbarIcon.Icon): boolean
	return (icon :: any).isSelected
end

-- select/deselect are typed without their source arguments, but the runtime forwards them into the
-- state change, so the call goes through the same cast.
local function setSelected(icon: TopbarIcon.Icon, selected: boolean, source: string): ()
	local untyped = icon :: any
	if selected then
		untyped:select(source, icon)
	else
		untyped:deselect(source, icon)
	end
end

--[[ Tables ]]--
local TopbarHandler = {
	-- Nothing here touches player data or an authored screen: the icons are built by TopbarPlus and
	-- the pages they open bind themselves. Starting late only means the row appears a frame later.
	priority = 10,
}

--[[ Handling ]]--
function TopbarHandler.OnInit(self: TopbarHandler): ()
	self.Janitor = Janitor.new()
	self.Icons = {}
end

function TopbarHandler.OnStart(self: TopbarHandler): ()
	for _, entry in ICONS do
		self.Icons[entry.Page] = self:CreateIcon(entry.Page, entry.Image, entry.Caption, entry.Order)
	end

	-- The store is the one that knows which page is up, so the icons read it rather than remembering
	-- their own clicks. Selecting an already-open page is a no-op inside Pages, which is what keeps
	-- this from bouncing against the click handlers below.
	local scope = Scope.Run(function(): ()
		Flux(function()
			local open = Pages.Current()

			for page, icon in self.Icons do
				if (page == open) ~= isSelected(icon) then
					setSelected(icon, page == open, "Pages")
				end
			end
		end, true)
	end)

	self.Janitor:Add(scope, "Destroy")
end

--- One topbar icon bound to `page`. Returns it so the caller can keep it.
function TopbarHandler.CreateIcon(
	self: TopbarHandler,
	page: string,
	image: string,
	caption: string,
	order: number
): TopbarIcon.Icon
	local icon = TopbarIcon.new()

	icon:setName(page)
	icon:setImage(image)
	icon:setCaption(caption)
	icon:setOrder(order)
	icon:align("Left")

	-- The store refuses a page while the tutorial holds it; the icon must not stay lit on a page that
	-- never opened.
	icon:bindEvent("selected", function(): ()
		if not Pages.Open(page) then
			setSelected(icon, false, "Topbar")
		end
	end)

	-- Only close what this icon opened: TopbarPlus deselects the previous icon when another one is
	-- picked, and that must not close the page the new icon just opened.
	icon:bindEvent("deselected", function(): ()
		if Pages.Current:peek() == page then
			Pages.Close()
		end
	end)

	self.Janitor:Add(function(): ()
		icon:destroy()
	end)

	return icon
end

export type TopbarHandler = typeof(TopbarHandler) & {
	Janitor: any,
	Icons: { [string]: TopbarIcon.Icon },
}

return TopbarHandler :: TopbarHandler
