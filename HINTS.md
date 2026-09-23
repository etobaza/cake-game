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
| `Occlusion` | Throttled obstacle checks (default true); exposes `Occluded` for tutorial instruction copy, not pathfinding. |

One `BindToRenderStep` callback runs after the camera for all hints. Only the winning hint draws. GUI bounds track visibility, ancestor clipping, scrolling and rotation; the generic geometry helper also retains support for the existing billboard ingredient controls. World targets use viewport projection, camera-relative edge direction and a smoothly interpolated shortest rotation arc. The two finger poses blend through a manually stepped Ripple tween with quintic easing, a rest, a short held press and a slower release. Smooth overlapping opacity avoids abrupt alpha clamps. Moving targets retain their animation phase; suppressed hints pause it. FingerPeriod controls the full cycle, with phase fractions in Configs/Hint.FingerPhases. Screen-edge fitting keeps the hand visible. Overlays do not capture input, move the character or control the camera.

`SetEnabled(false)` temporarily suppresses a hint without dropping its target. `IsVisible()` reports whether it won presentation, `IsOnScreen()` reports whether the visible marker is inside its safe projection region, and `GetBounds()` returns the active viewport rectangle (a point rectangle for world markers). These queries reflect the most recent render callback. `Destroy()` removes its render registration and GUI; destroying the GUI externally also releases the owner. If no owners remain, the shared callback unbinds.

Tuning and sprite IDs live in `Shared/Configs/Hint`. The separate caption below the finger has been removed; hints no longer create a text label or distance badge. `HintSurface` creates only a transient guidance overlay. Existing authored tutorial cards, controls, handbook and preview assets remain under `StarterGui.MainGui.Tutorial` and are driven by the presenter.

## Authored arrow beam

`ReplicatedStorage.Assets.VFX.ArrowBeam` is the original Part moved from Workspace, retaining its Beam, texture and two internal attachments. Save this place-only move with the place; Script Sync does not store the asset. `Shared/UI/HintBeam` lazily clones it for a winning world hint and keeps both endpoints in its own non-colliding, transparent, anchored Part. The start follows the local character with `Configs/Hint.Beam.PlayerOffset`; the finish follows the resolved world target. It hides within `MinDistance`, on target loss, during respawn, when another hint wins, or when switching to GUI guidance. Destroying the hint destroys its beam copy.

The authored negative texture speed is retained with endpoint assignment chosen to scroll toward the target. Stretch-mode repetition count follows distance to preserve the template's original arrow spacing. These properties follow the [Roblox Beam reference](https://create.roblox.com/docs/reference/engine/classes/Beam/Texture). Missing asset replication is retried without yielding in the render callback. Set `Beam = false` for a world hint that only needs the finger.

## Tutorial behavior

The introduction is enabled in `Configs/Tutorial`. Existing completed/skipped saves are preserved; no version bump resets them. Server-accepted cooking, serving and cleaning events remain the source of progression, protection and completion. The client resolves the next useful action from current kitchen state, including wrong carried items, interrupted recipes, burnt food and urgent collection.

The card immediately shows the action, input instruction, supporting copy and food/item preview. Small screens use a compact card instead of silently disabling guidance. Menus use the authored compact caption and GUI focus. Collapsing produces an explicit Resume control; the handbook and skip action remain available. Unrelated modal pages, the Roblox menu, respawn and the handbook suppress tutorial pointing. GUI focus dims the surrounding interface; world guidance leaves the bakery visible.

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

The full `scripts/check.ps1` gate passed with the pinned `luau-lsp 1.70.0`: regenerated sourcemap, Selene with zero warnings/errors, strict-header validation and whole-project analysis. Source synchronization and the authored tutorial hierarchy were inspected in Cake Funset Dev.

Edit-mode checks executed the stateless geometry module: 46 assertions covering diagonal rotations, shortest-arc transitions, offscreen and behind-camera projection, clipping and portrait/landscape safe bounds. Synthetic tutorial state checks covered 21 cases from recipe selection through ingredients, mixing, oven fuel, urgent collection, serving, cleaning, evening controls and animal harvest intent. These checks did not load or mutate player profiles.

Still requires a Studio Play feature test: render both finger images; inspect phone portrait/landscape and desktop; exercise Cmdr previews while moving and turning, including ArrowBeam direction and spacing; confirm collapse/resume, target loss, priority resumption and respawn cleanup; complete the introduction through accepted gameplay actions. No Play or screenshot test was performed during this implementation.

The subsequent [code review](CODE_REVIEW.md) fixed occupied-table seat targeting and stale hint query state after destruction. Seven Edit-mode lifecycle assertions passed for cleared state and idempotent cleanup; this fixture did not exercise client rendering. The full source gate passed again. Play feature checks above remain pending.
