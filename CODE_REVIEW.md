# Pending-change review — 2026-09-23

Reviewed the pending changes on `main` against `c707c37`, including the new hint modules, tutorial integration, garden production and presentation, authored UI bindings, Cmdr commands, and documentation. The review used `AGENTS.md`, `CODE_STYLE.md`, `ARCHITECTURE.md`, and `PACKAGES.md`, plus adjacent implementation and the active Cake Funset Dev hierarchy. This is a review of this change set and its integration points, not an exhaustive audit of every existing system.

## Findings fixed

1. **P2 — Animal output remained visible on vacant plots.** Moving milk and egg baskets into `Kitchen.Decoration` put them outside `VacantView`'s `Upgrades` traversal. On startup, or after `GardenWorld` restored authored properties during owner cleanup, unclaimed plots showed the upgrade-owned baskets and preview ingredients. [VacantView](ServerScriptService/Handlers/BuildingHandler/VacantView.luau) now captures each configured `OutputPath`, hides it on vacancy, and restores its original properties on claim.
2. **P2 — Occupied-table hints lost their seat target.** [Targets](ReplicatedStorage/Shared/UI/Tutorial/Targets.luau) cleared the seat frame when a matching dish model existed. The new generic focus adapter uses the frame or interaction anchor, so serving/cleanup guidance fell back to the table anchor. The resolver now retains the seat frame alongside the dish model.
3. **P3 — Destroyed hints reported stale presentation state.** [Hint](ReplicatedStorage/Shared/UI/Hint.luau) destroyed resources without clearing `Visible`, `OnScreen`, `Occluded`, or `Bounds`. Callers retaining a handle after duration expiry could still observe an active hint. Destruction now clears the target and presentation state, disables the owner, and remains idempotent.
4. **Documentation consistency.** [UI_VERIFICATION.md](UI_VERIFICATION.md) now distinguishes its earlier disabled-tutorial test configuration from the subsequently enabled introduction. Historical Play claims were not repeated or treated as verification of this review's fixes.

## Style and architecture assessment

- New hint presentation uses an owned client module and one render binding; tutorial and Cmdr preview lifetimes are separate. Visual tuning remains in `Configs/Hint`. The debug handler declares its UI and interaction dependencies.
- Server garden actions continue through the owning building handler. Harvest range resolves the kitchen output, while brushing range resolves the animal. Saved stock and carried-item changes use the existing data proxies and inventory owner. The existing `PantryHandler` dependency covers excess-stock migration.
- `Bus.Hints.Debug` remains a one-way presentation message. `hinttest` uses the existing server `TutorialDebug` authorization hook and bounds its duration, angle, and path length. It does not write player profiles.
- Authored screens remain bound through the existing UI system. The generated hint surface is an owned, non-interactive overlay. Package manifests, generated dependencies, persistence store identity, and receipt ownership are unchanged.
- No additional actionable blocker was found in the reviewed source. Passing static checks does not establish gameplay or device-layout correctness.

## Verification performed during this review

- Full `scripts/check.ps1` passed after the fixes: regenerated sourcemap; Selene with zero errors, warnings, or parse errors; first-party strict headers; whole-project Roblox-aware analysis with Rokit-pinned `luau-lsp 1.70.0`.
- Confirmed all three fixes had synchronized into Cake Funset Dev, place `85619104317376`, in Edit mode. Confirmed the authored tutorial `Compact`, bakery header `Title`, ArrowBeam asset, and milk/egg basket hierarchy exist.
- Executed 72 Edit-mode assertions on unparented clones of authored baskets across vacant, claim, release, and reclaim transitions. Checked visibility, collision, and query restoration; destroyed the fixture afterward. Authored objects and profiles were unchanged.
- Executed seven Edit-mode hint lifecycle assertions using a temporary GUI and stub resource owners: cleared visibility, screen state, bounds, target and active state; single cleanup; repeated-destroy safety. This did not exercise the client render loop.
- Checked the final diff for whitespace errors and checked local documentation links.

## Remaining runtime checks

No Studio Play session or screenshot was started during this review. Play permission was requested but had not been granted. The existing Edit-mode `AdminTestMockData = true` attribute was preserved; no player profile was loaded or changed by these checks.

After an authorized fresh Play session with mock data, verify occupied-table seat guidance, hint duration/priority/respawn cleanup, animal basket pickup/return and distance rejection, vacant-plot release/reclaim, and introduction completion. Desktop and phone presentation, including ArrowBeam direction and spacing, still need feature-level verification. Existing authored UI and world asset edits must be saved/deployed with the place separately; a Git push only publishes repository files.
