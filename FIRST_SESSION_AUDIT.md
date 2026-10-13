# First-session audit (TaskList 3.1)

Date: 2026-10-12. Place: Cake Funset Dev (85619104317376), Studio Play, one client, desktop viewport 1891 by 1113, keyboard and mouse.

## Method

- A fresh profile came from the opt-in `AdminTestMockData` mock store. Live profiles and store identities were not touched. The attribute was removed afterwards.
- A temporary client logger wrapped the tutorial presenter's `Set`, `UIHandler:Toast` and the page store. It recorded every goal change (id, title, hint, stage), toast and page with a timestamp.
- The session was driven through Studio MCP with character navigation, the E key and virtual mouse clicks on the real buttons. Where the engine chose a different prompt, the camera was turned toward the intended station by script. Each such case is listed as a finding.
- Timestamps include MCP tool latency, so they show order and gaps, not human pace. The shift was ended early through `DayCycleHandler:EndShift` to reach the evening; the shift's natural end was not observed.
- No screenshots were taken. Everything below comes from the replicated state, GUI text and the log.

## Observed flow

| t (s) | Goal | Player action | Note |
| --- | --- | --- | --- |
| 0 | `intro_broom` 1/4 "First, pick up the broom" | Walk to the rack, E | Three spills exist; only `spill_1` is visible and highlighted. |
| 26 | `intro_sweep_spill_1` "Sweep the dough spill" | E at about 5.2 studs from the spill center did nothing; E at about 3 studs swept | See finding 11. |
| 72 | `intro_return_broom` "Floor clean! Return the broom" | E at the rack | The return step appeared only after an accepted sweep, as intended. |
| 91 | `choose_bread` 2/4 "Go to your mixer" | E 4 studs from the mixer took **Flour** | See finding 1. |
| 199 | `start_bread` "Start French Baguette" | Click Start | Only the tutorial recipe row is shown. |
| 215 | `close_recipes` "Return to your mixer" | Click X | The page is still open; see finding 5. |
| 230-266 | `fetch_flour` → `load_flour` → `mix` | Flour, Add, Mix | One flour is enough. |
| 278-296 | `wait_mixer_1` → `collect_mixer_1` → `load_dough` | Take, walk to the oven | |
| 324-363 | `wood_oven_1` → `fuel_oven_1` → `wait_oven_1` → `collect_oven_1` | Log, Add firewood, Take | The oven plate counts "Burns in 26s". |
| 372 | `open` 3/4 "Open your bakery" | Click the HUD clock | |
| 393-403 | `guest_arriving` → `take_order` | E at seat 1 ("Take order / Guest #1") | The bubble shows "! Take my order!". |
| 445 | `order_card` "Tap your guest's order card" | E (Serve) without tapping the card | See finding 6. |
| 461-480 | `eating` "First sale! +$3.09" → `clean_table` 4/4 → `completed` | E (Clean) | The HUD, topbar and new Group Reward icon appear on completion. |
| 484 | none | idle | Four guests at once; see finding 2. |
| 507 / 532 / 542 | coach nudges as toasts | idle | "A guest is ready to order", then "Pick a recipe at the mixer first", then "Go to your mixer". |
| 542-631 | none | idle | Two guests wait for food with no guidance; see finding 2. |
| 636 | coach "Hurry: a guest is about to leave" | `EndShift` | |
| 652 | `upgrade_open` "Put your earnings into upgrades" | Click the Upgrades tab | The report shows "Upgrades available 3" at 28 coins. |
| 680 | `upgrade_pick` "Pick Display Counter" | Click Purchase | The node was already selected; see finding 8. |
| 722-736 | `open_next_menu` → `next_menu` | Click Menu, then Next Day | |
| 758-760 | none (Day 2 Prep) | idle | The Upgrades page opened and closed by itself; see finding 9. |
| 790 | coach "Bake a dish ahead, then open" | idle | The only day-2 guidance in 40 seconds. |

The run produced no client or server errors or warnings, apart from the logger's deliberate test lines.

## Findings

Ordered by expected impact on a new player.

1. **The mixer prompt loses focus to Flour/Sugar.** Standing 3.9 studs from the mixer and 7.9 studs from the flour bag, with the spawn camera facing +X, E took Flour. Holding an ingredient, the only prompt was "Put back"; the mixer prompt never appeared. The goal still said "Go to your mixer" without asking the player to free their hands. Engine prompt selection weights camera direction. Possible fixes: a free-hands branch in `choose_*` when an ingredient is held, and a shorter activation distance or reach for the counter dispensers (related to 11.5).
2. **Rush after the tutorial with silent guidance.** Within about five seconds of completion, four guests arrived (two choosing, two arriving). The tutorial goal went empty. Coaching appeared only as short toasts at about 26, 48 and 58 seconds, then nothing for 90 seconds while two guests waited for food. Two of the four guests never sat down. Suggest ramping arrivals after the introduction and keeping a persistent coach line while a guest waits.
3. **Orders accept themselves.** Unattended guests went from Choosing to Waiting after `TakeOrderFallbackSeconds` (25 seconds). Outside the tutorial the player never has to learn Take order, and the order card appears without any action.
4. **Coach copy reads like a tutorial restart.** Mid-shift coaching reused "Go to your mixer. Use the mixer to open its recipes. Let's start with French Baguette."
5. **"Return to your mixer" while the recipe page is open.** The `close_recipes` title does not say to close the page, and the player has to find the X. The hint only says the recipe is selected.
6. **The order card step comes after cooking.** The introduction cooks first, then opens, then takes the order. When the order arrives, the player already holds the dish and Serve is offered. "Tap your guest's order card" is noise at that point, and Serve completes the step without the card. This teaches a cook-ahead flow rather than reading orders.
7. **Small first payout and a rounded price.** The first sale paid $3.09 (25 → 28.09). Display Counter showed price "5" but charged 5.25 (`Format.Number` rounds the display), so the shown price and the charge differ.
8. **The upgrade lesson asks for a click that is already done.** "Pick Display Counter: tap this node" appears while `ShopHandler` has already selected it and the footer shows Purchase.
9. **Unexplained Upgrades flash on day 2.** About 10 seconds after Next Day, the page store switched to Upgrades for about 2 seconds and closed with no input. Not diagnosed. It may be the purchase reveal or the lesson re-resolving after the day change. Needs a reproduction.
10. **Day 2 preparation has almost no guidance.** For 40 seconds nothing was shown, then one toast: "Bake a dish ahead, then open". The clock-as-open-button is taught once, on day 1 only.
11. **Low confidence: sweep reach.** E at about 5.2 studs from the spill center did not sweep; the same action at about 3 studs did. Whether the prompt was visible at 5.2 studs was not checked.
12. **Low confidence: stale prompt.** At the oven holding dough, before the camera was turned, the shown prompt was still the mixer's "Recipes", about 60 studs away. Needs a reproduction.

## What worked

- The broom lesson waits for an accepted sweep before asking to return it. The spill is highlighted, and the stage counter runs 1/4 to 4/4.
- Station plates show useful passive status ("Needs firewood", "Burns in 26s").
- The guest bubble shows "! Take my order!" and then the dish and seat number.
- The evening flow (report → upgrades lesson → menu → Next Day) completed. The topbar, including the group reward icon, appears only after the introduction.

## Not covered

Touch and gamepad input, phone layouts, burning or running out of fuel, wrong-dish serving, rare guests, a level-up, the shift's natural end, and multiple players.
