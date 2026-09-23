# Mikey UI verification

Verified in Cake Funset Dev, place `85619104317376`, on 2026-09-23.

## Scope and changes

The edited assets are in `StarterGui.MainGui`. `StarterGui.Mikey` remains the visual reference; its ScreenGuis are disabled to prevent sample HUD elements from appearing over the game.

Outer sizes of all nine `MainFrame` panels are unchanged. Internal artwork, label placement, Funds spacing, reward cards, recipe cards, ribbon titles, and icon aspect ratios were repaired. Gameplay content and existing responsive layouts remain adaptations rather than pixel-identical copies of the designer's static screens.

The initial authored comparison covered 16,973 mapped style properties: 16,903 matched the reference baseline. The 70 intentional differences were semantic icons using `ScaleType.Fit` instead of `Stretch`. The later requested Greenhouse border correction deliberately changes one additional image from the reference. New title artwork and internal layout corrections were also reviewed in screenshots.

## Checks performed

- Restarted Studio Play after the source and authored-asset changes. Test sessions used `AdminTestMockData`; the runtime data handler confirmed mock profiles before reward fixtures.
- Inspected screenshots of Upgrades (Store, Kitchen, Greenhouse), Inventory/Menu, RecipeToCook, Store, Playtime, DailyRewards, Codes, Report, shared BakeryMenu header, live HUD, and Status toast.
- Exercised DailyRewards and Playtime claims with mouse clicks, inspected claimed/countdown states, and checked empty-code feedback and panel closing. No paid purchases were made.
- Exercised the real day transition to Summary, then clicked Menu and Next Day. Checked both evening header states.
- Inspected selected recipe outlines and the cooking detail panel with mock data. Checked Inventory, Store, and Playtime scrolling to their last content rows.
- Inspected all eight pages with the existing compact layout using a simulated `390 x 844` available area. This is a responsive-layout check, not a physical-device or Studio device-emulator test. Corrected DailyRewards compact caption/price overlap and rechecked it after restarting Play.
- Instantiated the existing Tutorial presenter with a temporary visual fixture and inspected its card and populated handbook. The tutorial was disabled during this UI verification; the later hint implementation enabled it. Tutorial progression was not tested in this pass.
- Full `scripts/check.ps1` passed after the three UI source changes: regenerated sourcemap, Selene, and project-pinned luau-lsp 1.70.0 full-project analysis.

## Limits and persistence

Latest connector/border correction: pixel alignment alone did not resolve the reported Store defect. Two routes ran only two pixels apart. The branch from Display Counter 2 now enters the left-side route to Display Counter 3 instead of adding a second adjacent horizontal segment. Twenty-five redundant collinear segments were merged across the three categories. Kitchen/Garden coverage was compared as logical pixel sets before/after merging: no missing or added pixels. Non-connector sizes and positions remained unchanged. Greenhouse now uses the same background image as Store/Kitchen, explicitly overriding the original darker Mikey border at the user's request. Fresh Play screenshots covered all three categories and the compact Store layout; reviewed output had no game errors. Changes are in StarterGui.

Connector follow-up: the 85 authored category-tree segments had half-pixel endpoints and one-pixel widths. Their endpoints were snapped to the logical pixel grid and joined with overlapping two-pixel strokes. Three obsolete Kitchen segments leading to the unused final slot were hidden. Card sizes and positions were compared before/after and remained unchanged. Fresh Play screenshots covered Store, Kitchen, and Greenhouse; reviewed game output contained no errors. These are StarterGui asset edits, with no additional Luau source change.

Follow-up: the user identified the inconsistent-looking Greenhouse tab and thick selected upgrade border. Greenhouse uses a different background image in Mikey itself (`133866076507566`, versus `86430257398433` for Store/Kitchen), so it was preserved. `ShopHandler` was tripling the selected node stroke and replacing its cream fill with white; both overrides were removed. A fresh Play screenshot and selection click confirmed the authored stroke thickness (`0.0317460335791111`) and unchanged `70 x 70` node size. The full source gate passed again. Upgrade-name text is gameplay content added to the originally empty reference slots, not original Mikey artwork.

Report, Tutorial, Status, and the complete live HUD have no exact full-screen counterpart in Mikey; their shared palette and decorations were reviewed. Dynamic gameplay content and panel dimensions differ from the static reference by design.

No game-script errors were observed in the reviewed Play output. Roblox's automation plugin emitted CoreGUI cursor-movement warnings during mouse tests; the tested controls still changed state.

Temporary runtime test scripts disappear on Stop. The mock attribute is restored after testing. The authored StarterGui changes are place-only and must be saved with the place; Script Sync and Git contain only the source changes. The place was not published.
