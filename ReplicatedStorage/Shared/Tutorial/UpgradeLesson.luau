--!strict
-- First-shift shopping guidance stays optional, affordable and out of the running shift.
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.GameTypes)
local Tree = require(script.Parent.Parent.Configs.UpgradeTree)
local UpgradeTabs = require(script.Parent.Parent.Configs.UpgradeTabs)
local Upgrades = require(script.Parent.Parent.Configs.Registries.Upgrades)

local UpgradeLesson = {}

function UpgradeLesson.Resolve(
	cloud: any,
	session: any,
	page: string,
	facts: Types.TutorialContext
): Types.TutorialGoal?
	local saved = cloud.Tutorial
	if
		saved.Status ~= "Completed"
		or saved.Collapsed
		or saved.Lessons.Upgrades
		or saved.Lessons["Dismissed:Upgrades"]
		or not saved.Lessons.UpgradesDue
		-- The evening header has no Upgrades tab; the lesson waits for the HUD in the next Prep.
		or session.Day.Phase ~= "Prep"
	then
		return nil
	end
	local progress = Upgrades:GetProgress(cloud.Base.Upgrades, cloud.Level, cloud.Cash)
	local purchase = progress.Recommended
	local entry = purchase and Upgrades:Get(purchase.Id)
	-- Spending is never demanded when unaffordable; the normal next-menu lesson remains usable.
	if not purchase or not entry or progress.AffordableCount == 0 then
		return nil
	end
	local title = Upgrades:GetDisplayName(entry.id, purchase.Level - 1)
	local goal: Types.TutorialGoal?
	if page ~= "Upgrades" then
		goal = State.Gui(
			"upgrade_open",
			"Put your earnings into {upgrades}",
			"Open Upgrades. The cheapest available purchase is selected for you.",
			"UI.HUD.SideBtns.Upgrades.Btn"
		)
	elseif facts.upgradeCategory ~= entry.category then
		goal = State.Gui(
			"upgrade_category",
			`Find {title}`,
			"Choose this category to see your next upgrade.",
			`Upgrades.MainFrame.Main.Top.{UpgradeTabs.NameByCategory[entry.category]}`
		)
	elseif facts.upgradeSelectedId == entry.id and facts.upgradeSelectedLevel == purchase.Level then
		-- ShopHandler already selects the recommended node on open, so asking for that tap again
		-- would point at a finished click; the lesson goes straight to Purchase.
		goal = State.Gui(
			"upgrade_buy",
			"Buy {" .. title .. "}",
			"Press Purchase. Then see what changed in your bakery; Skip returns early.",
			"Upgrades.MainFrame.Main.Bottom.Status.Prchased"
		)
	else
		for index, cell in Tree.Categories[entry.category] do
			if cell.Id == entry.id and cell.Level == purchase.Level then
				goal = State.Gui(
					"upgrade_pick",
					"Pick {" .. title .. "}",
					"Tap this available node to see its benefit and price.",
					`Upgrades.MainFrame.Main.Tree.Content.{table.concat(Tree.Slots[index], ".")}`
				)
				break
			end
		end
	end
	if goal then
		goal.topic = "Upgrades"
	end
	return goal
end

return UpgradeLesson
