# Guidance review — 2026-09-23

The initial review below was committed as `8b425ab`. The follow-up section records the subsequent style refactor, tutorial card removal, and authorized Play verification. Initial verification limits are historical, not the current test status.

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
- The initial pass missed excessive control-flow nesting, dense statement groups, scattered presentation tuning, and oversized tutorial UI. The follow-up below corrects those omissions. Passing static checks alone does not establish gameplay or device-layout correctness.

## Verification performed during this review

- Full `scripts/check.ps1` passed after the fixes: regenerated sourcemap; Selene with zero errors, warnings, or parse errors; first-party strict headers; whole-project Roblox-aware analysis with Rokit-pinned `luau-lsp 1.70.0`.
- Confirmed all three fixes had synchronized into Cake Funset Dev, place `85619104317376`, in Edit mode. Confirmed the authored tutorial `Compact`, bakery header `Title`, ArrowBeam asset, and milk/egg basket hierarchy exist.
- Executed 72 Edit-mode assertions on unparented clones of authored baskets across vacant, claim, release, and reclaim transitions. Checked visibility, collision, and query restoration; destroyed the fixture afterward. Authored objects and profiles were unchanged.
- Executed seven Edit-mode hint lifecycle assertions using a temporary GUI and stub resource owners: cleared visibility, screen state, bounds, target and active state; single cleanup; repeated-destroy safety. This did not exercise the client render loop.
- Checked the final diff for whitespace errors and checked local documentation links.

## Initial runtime limits (before follow-up)

No Studio Play session or screenshot was started during this review. Play permission was requested but had not been granted. The existing Edit-mode `AdminTestMockData = true` attribute was preserved; no player profile was loaded or changed by these checks.

After an authorized fresh Play session with mock data, verify occupied-table seat guidance, hint duration/priority/respawn cleanup, animal basket pickup/return and distance rejection, vacant-plot release/reclaim, and introduction completion. Desktop and phone presentation, including ArrowBeam direction and spacing, still need feature-level verification. Existing authored UI and world asset edits must be saved/deployed with the place separately; a Git push only publishes repository files.

## Follow-up findings and changes

1. **Control-flow readability.** Split target resolution, GUI/world drawing, finger placement, and occlusion updates into focused helpers. Flattened ancestor visibility checks and duplicate-name highlight traversal. Added blank lines between guards, calculations, and side effects instead of relying on formatter output alone.
2. **Animation ownership.** Extracted `HintAnimation`, a manually stepped four-state FSM (`Rest`, `Press`, `Hold`, `Release`) composed with the existing Ripple motion. Named state transitions and phase fractions replace index arithmetic. Suppression pauses the animation; changing a target resets it. No ECS or additional framework is needed for one owned animation.
3. **Tuning and duplication.** Moved visual sizes, rotation, occlusion, retry, and preview tuning to `Configs/Hint`; kept named numerical tolerances beside geometry. `Geometry.Inset` replaces duplicated safe-rectangle calculations. Cmdr uses a typed presenter dispatch table and one preview cleanup owner.
4. **Hint state correctness.** Disabling occlusion and switching to GUI now clear stale obstruction state. Destroyed hints cannot be enabled again. Discriminated GUI/world results replace optional fields and rendering casts.
5. **Tutorial presentation.** Disabled the legacy tutorial ScreenGui on every platform, removing the card, Resume banner, handbook, and help menu from presentation. Deleted obsolete card layout and item preview modules and removed their unused adapter work. The tutorial announces each eligible goal through the existing toast, without replacing active feedback. Saved progress and collapsed preferences remain compatible.
6. **Notification size and lifetime.** Added `StatusLayout` and `Configs/Notifications` around the authored status frame. Compact toasts are bounded to 240 by 32 pixels, wide toasts to 360 by 48, with smaller text and no decorative tag/lines. An explicit Flux cleanup callback destroys the typed Janitor; no `any` return is needed at this new boundary.

These changes separate state transitions, target resolution, drawing, and authored notification layout without changing the public hint API or adding another bootstrap/network/persistence path. Named configs and shared helpers address DRY; plain helpers, composition, and a small FSM keep responsibilities narrow without a framework migration.

## Follow-up verification

- Full `scripts/check.ps1` passed: regenerated sourcemap, zero Selene errors/warnings, strict headers, and complete Roblox-aware analysis using pinned `luau-lsp 1.70.0`.
- Fresh Studio Play used the existing `AdminTestMockData = true`; runtime confirmed mock persistence. Final source synchronization was checked before restart.
- The client feature suite passed 213 assertions at each actual viewport: phone portrait 401 by 777, phone landscape 749 by 361, and desktop 1893 by 1201. It exercised animation transitions/reset/clamping, live GUI movement, priority/tie ordering, pause/resume, clipping, resolver recovery, duration, explicit/external destruction, world projection, Model/Attachment targets, occlusion changes, beam endpoints, rotated bounds, and both authored Door siblings.
- Tutorial assertions checked that the card/banner never becomes enabled, notification dimensions follow the viewport, existing feedback is not replaced, and an announced goal does not repeat each frame. Fixtures were destroyed after each run.
- A separate mock-session character respawn test confirmed beam disappearance, recovery following the new character, and cleanup. Cmdr `gui`, `world`, `demo`, and `hide` commands ran through the real client/server dispatcher. Fourteen additional assertions checked preview ownership/visibility, cleanup after a missing target, and rejection of invalid mode, duration, and rotation.
- Final client/server console inspection, whitespace checks, and local documentation-link checks completed. Simulator settings and Edit mode were restored; the pre-existing mock-data attribute was preserved.

These are runtime assertions, not screenshot approval or physical-device certification. Complete introduction gameplay, live save/rejoin behavior, beam artwork/texture appearance, and physical console controls were not tested. The earlier garden fixes retain their documented Edit-mode verification scope. Publishing to Git `main` does not deploy place-only assets.
