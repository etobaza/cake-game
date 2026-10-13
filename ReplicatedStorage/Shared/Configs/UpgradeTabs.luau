--!strict
-- Upgrades screen category tabs, in the order they are drawn. Name is the authored button under
-- Upgrades.MainFrame.Main.Top; ShopHandler binds them and the first-purchase lesson points at them.
local GameTypes = require(script.Parent.Parent.GameTypes)

export type Tab = { Name: string, Category: GameTypes.UpgradeCategory }

local TABS: { Tab } = {
	{ Name = "Store", Category = "Cafe" },
	{ Name = "Kitchen", Category = "Kitchen" },
	{ Name = "GreenHouse", Category = "Garden" },
}

local names: { [string]: string } = {}
for _, tab in TABS do
	names[tab.Category] = tab.Name
end

return {
	Tabs = TABS,
	-- Category -> authored tab button name.
	NameByCategory = names,
}
