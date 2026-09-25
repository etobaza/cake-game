# Hints and tutorial guidance

`ReplicatedStorage.Shared.UI.Hint` is a client presentation module. Any client system can use it without starting the tutorial, changing progress, or sending a remote. The tutorial uses the same module through `UI/Tutorial/Focus`.

## Use from a client owner

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hint = require(ReplicatedStorage.Shared.UI.Hint)

local hint = Hint.new({ Priority = 30 })
owner:Add(hint, "Destroy") -- The caller's existing Janitor.

hint:Gui(button, { Key = "open_recipes" })
hint:World(attachment, { Key = "visit_mixer", WorldOffset = Vector3.new(0, 1, 0) })
hint:Hide() -- Keep this owner available for another target.
hint:Destroy() -- Release the overlay and registration; safe to call again.
```

`Gui` accepts a `GuiObject` or a non-yielding function returning a `GuiObject?`. `World` accepts a `BasePart`, `Model`, `Attachment`, `Vector3`, or a non-yielding function returning one of those or nil. A resolver returning nil temporarily hides its hint and allows another eligible hint to show. This supports streamed/recreated targets without keeping dead instances alive. Resolver errors warn once until a successful resolution.

Use `IncludeDescendants = true` for a composite GUI target whose visible artwork extends outside its container. Its focus rectangle includes visible, ancestor-clipped descendants and follows their rotation/scale. The tutorial clock uses this for its sign, ribbon and time label. Focus padding is clipped at the viewport edge, independently of the safe margin used for finger/world placement, so top-aligned HUD targets are not cut off by that margin.

```lua
local Interact = require(ReplicatedStorage.Handlers.InteractHandler)
local hint = Hint.new({ Priority = 30, Duration = 12 })
hint:World(function(): BasePart?
    return Interact:GetProp("mixer_1")
end, { Key = "mixer", Rotation = 60 })
```

Declare `InteractHandler` in the calling handler's `dependencies` when using this example. Resolve other authored world content through `Shared/World` or its owning handler.

## Options and ownership

Defaults supplied to `Hint.new` are merged with each `Gui` or `World` call. Per-call options do not leak into the next call.

| Option | Behavior |
| --- | --- |
| `Key` | Stable identity for a moving/re-resolved target. Repeated calls with the same key keep animation phase and lifetime. Change the key to restart. |
| `Priority` | Highest eligible value wins. Defaults: ordinary 0, tutorial 20, Cmdr preview 100. Most recently changed target wins ties. Lower hints resume when the winner disappears. |
| `Duration` | Optional wall-clock lifetime in seconds from target selection; destroys the owner even while suppressed. Omit for caller-managed lifetime. |
| `Rotation` | Optional fixed degrees, including negative and diagonal angles. Omit for automatic rotation. |
| `FingerSize`, `Scale` | Optional pixel size and multiplier. Default size responds to viewport height; final size is bounded to fit small screens. |
| `FingerPeriod` | Duration of the two-pose finger animation cycle. |
| `Padding`, `Dim`, `TargetPoint` | GUI focus padding, optional dimming (default on), and normalized target point (default center). |
| `WorldOffset` | Offset from the live world position. |
| `Beam` | Show the authored player-to-target ArrowBeam for a world hint (default true). GUI hints never show a beam. |
| `Occlusion` | Throttled obstacle checks (default true); exposes `Occluded` to the caller, not pathfinding. |

One `BindToRenderStep` callback runs after the camera for all hints. Only the winning hint draws. GUI bounds track visibility, ancestor clipping, scrolling and rotation; the generic geometry helper also retains support for the existing billboard ingredient controls. World targets use viewport projection, camera-relative edge direction and a smoothly interpolated shortest rotation arc. The two finger poses blend through a manually stepped Ripple tween with quintic easing, a rest, a short held press and a slower release. Smooth overlapping opacity avoids abrupt alpha clamps. Moving targets retain their animation phase; suppressed hints pause it. FingerPeriod controls the full cycle, with phase fractions in Configs/Hint.FingerPhases. Screen-edge fitting keeps the hand visible. Overlays do not capture input, move the character or control the camera.

`SetEnabled(false)` temporarily suppresses a hint without dropping its target. `IsVisible()` reports whether it won presentation, `IsOnScreen()` reports whether the visible marker is inside its safe projection region, and `GetBounds()` returns the active viewport rectangle (a point rectangle for world markers). These queries reflect the most recent render callback. `Destroy()` removes its render registration and GUI; destroying the GUI externally also releases the owner. If no owners remain, the shared callback unbinds.

Tuning and sprite IDs live in `Shared/Configs/Hint`. `HintAnimation` owns the four named states `Rest`, `Press`, `Hold`, and `Release`, with explicit next states and phase fractions in the config. The separate caption below the finger has been removed; hints no longer create a text label or distance badge. `HintSurface` creates only a transient guidance overlay. The legacy authored tutorial ScreenGui remains disabled on every device.

## Authored arrow beam

`ReplicatedStorage.Assets.VFX.ArrowBeam` is the original Part moved from Workspace, retaining its Beam, texture and two internal attachments. Save this place-only move with the place; Script Sync does not store the asset. `Shared/UI/HintBeam` lazily clones it for a winning world hint and keeps both endpoints in its own non-colliding, transparent, anchored Part. The start follows the local character with `Configs/Hint.Beam.PlayerOffset`; the finish follows the resolved world target. It hides within `MinDistance`, on target loss, during respawn, when another hint wins, or when switching to GUI guidance. Destroying the hint destroys its beam copy.

The authored negative texture speed is retained with endpoint assignment chosen to scroll toward the target. Stretch-mode repetition count follows distance to preserve the template's original arrow spacing. These properties follow the [Roblox Beam reference](https://create.roblox.com/docs/reference/engine/classes/Beam/Texture). Missing asset replication is retried without yielding in the render callback. Set `Beam = false` for a world hint that only needs the finger.

## Tutorial behavior

The introduction is enabled in `Configs/Tutorial`. Existing completed/skipped saves are preserved; no version bump resets them. Server-accepted cooking, serving and cleaning events remain the source of progression, protection and completion. The client resolves the next useful action from current kitchen state, including wrong carried items, interrupted recipes, burnt food and urgent collection.

New introductions begin with a `Sweep` stage: take the broom, clean the introductory spill, and return the broom. `CleaningHandler:PrepareTutorial` owns the authored spill and retries while the bakery is loading. The stage advances only after accepted mopping, an empty spill set, and no carried broom. The additive `PreparedFloor` action records completion. Existing cooking milestones, a selected recipe, and live batches bypass this opening so resumed/reset kitchens do not lose food. Missing authored spills do not block the rest of the introduction. Opening early keeps the protected clock and holds the first guest until `Sweep` ends. `IntroCleanup` can disable this opening task for new runs.

The remaining route teaches recipe selection, ingredients, mixing, dough, oven fuel, collection, opening, the first guest's order, serving, and table cleanup. A wrong table or a still-dirty/occupied taught seat cannot complete the introduction. Normal spill generation resumes after completion.

The tutorial card, handbook, help menu, and Resume banner are removed from presentation on all platforms. Guidance uses the hand and a short title toast per eligible goal. A goal must remain eligible for `GoalSettleSeconds` (0.25 seconds) before announcement; actionable goals can repeat after `ReminderSeconds` (18 seconds). A busy toast keeps priority; the tutorial retries after it closes. A clipped recipe target uses its scroll instruction. `Configs/Notifications` limits compact toasts to 240 by 32 pixels and wide-screen toasts to 360 by 48, with viewport-responsive typography. The old preview and card-layout modules are removed.

At a world target, the Beam and finger lead toward its interaction point. Once that exact prop's actionable prompt is visible, the finger moves to the clickable/tappable prompt and the Beam hides. This prompt focus does not dim the bakery. Waiting for mixing, baking, arrivals, or eating hides the pressing finger; the short order-card lesson remains highlighted. Pointer changes never activate a prompt or advance server progress themselves.

An unrelated modal page redirects an active tutorial goal to that page's close/back arrow. The visible, interactable `Exit` or `CloseButton` is resolved through `UIHandler`, with the shared `BakeryMenu` header preferred for Inventory, Report, and Upgrades. This also applies while the gameplay goal is waiting; closing the window is actionable. Required recipe pages and the locked evening Report/Menu flow retain their intended guidance. The current task resumes after closing, without resetting progress. Optional upgrade guidance remains available after the introduction.

The Roblox menu, respawn, and the saved collapsed preference suppress tutorial pointing. Hidden, disabled, stale-page, or locked close controls are never targeted. GUI focus dims the surrounding interface; world guidance leaves the bakery visible. Existing debug commands can still show, hide, skip, or reset tutorial progress; no save migration is introduced.

Animal harvest hints resolve the kitchen `AnimalProduce` target while brushing still resolves the animal. Evening lessons resolve the shared `BakeryMenu` header's Menu/Next Day controls.

## Cmdr

Commands use the existing `TutorialDebug` group: allowed in Studio, and restricted to the server admin registry in published servers. Hint previews affect only the executor and never modify a profile.

```text
hinttest gui
hinttest world mixer_1
hinttest world mixer_1 30 60
hinttest world mixer_1 30 -45
hinttest gui Time 30 45
hinttest demo
hinttest hide
```

Arguments: `hinttest [gui|world|demo|hide] [target|-] [seconds] [auto|degrees]`. Duration is 1–300 seconds, default 30. GUI targets are paths relative to `UIHandler.HudRoot`, or explicit `PlayerGui.` paths. World targets are owned prop IDs from `InteractHandler`. The demo moves a world-space point around the starting location; walk and turn the camera to inspect continuous angles and edge indicators. Close the console after issuing a command. A missing target produces a HUD message.

`tutorialtest` is an alias for `tutorialreset`. It resets **saved tutorial progress and optional lesson flags**, retaining the current kitchen and existing reset behavior. It is not a profile-safe preview. Use an isolated mock session for repeatable new-player testing. Existing `tutorialstatus`, `tutorialshow`, `tutorialhide`, `tutorialskip` and `tutorialcomplete` remain available.

## Verification

The unrelated-page recovery change passed the full Luau gate and 68 synthetic Edit-mode assertions. These covered all eight routed pages, restoration of the original goal, waiting/urgent recovery, required recipe selection, optional upgrades, the locked evening flow, shared-header ownership, hidden/disabled buttons, stale pages, alternate close names, and panel fallback. Tests evaluated fresh synced module source to avoid Studio's Edit-mode `require` cache, using unparented UI fixtures and a geometry stub for target selection. No Play session or visual click-through was performed for this change.

The full `scripts/check.ps1` gate passed with the pinned `luau-lsp 1.70.0`: regenerated sourcemap, Selene with zero warnings/errors, strict-header validation and whole-project analysis. Source synchronization and the authored tutorial hierarchy were inspected in Cake Funset Dev.

Edit-mode checks executed the stateless geometry module: 46 assertions covering diagonal rotations, shortest-arc transitions, offscreen and behind-camera projection, clipping and portrait/landscape safe bounds. Synthetic tutorial state checks covered 21 cases from recipe selection through ingredients, mixing, oven fuel, urgent collection, serving, cleaning, evening controls and animal harvest intent. These checks did not load or mutate player profiles.

The subsequent [code review](CODE_REVIEW.md) fixed occupied-table seat targeting and stale hint query state after destruction, then refactored control flow and removed the tutorial card. Authorized Studio Play tests used the existing `AdminTestMockData = true` setting. Client assertions covered the animation FSM, live GUI movement, clipping, priority/tie ordering, suppression/resumption, expiry, dynamic target recovery, destruction, world projection, occlusion, rotated marker bounds, beam endpoints, both door leaves, and notification ownership. Device simulation exercised phone portrait (401 by 777), phone landscape (749 by 361), and desktop (1893 by 1201). Each layout passed 213 assertions, including the absence of the card/banner and bounded toast dimensions.

Separate runtime tests exercised actual character respawn and beam recovery/cleanup, plus Cmdr preview commands through the real client/server route. No screenshots or physical console/device tests were performed. Full introduction completion through accepted gameplay actions, visual artwork/beam texture inspection, and published-session behavior remain outside these checks. The passing static and runtime checks do not establish that all gameplay is defect-free. Git publishes source; authored place-only assets require the place deployment workflow.

The subsequent introductory-cleanup change passed 57 synthetic assertions in Studio Edit mode. They covered the complete state/goal sequence, multiple spills, broom return, unavailable spill assets, existing progress, rejoining after mopping, a reset with carried dough, wrong-item recovery, urgent oven collection, the exact guest seat, rejected wrong/dirty tables, and idempotent completion. These fixtures used plain tables and did not start Play or touch profiles. Source sync was checked in Cake Funset Dev. Both finger poses and the authored Beam texture loaded successfully through `ContentProvider:PreloadAsync` on temporary ImageLabels and an unparented Beam-template clone; preloading bare asset-ID strings was not a reliable check. Actual new-player Play traversal and visual desktop/mobile inspection of prompt switching remain pending for this change.
