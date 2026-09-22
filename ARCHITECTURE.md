# Architecture

## Runtime layout

The repository mirrors Roblox DataModel services on disk. Studio's Script Sync keeps the place and this folder in step (scripts only; it maps directories literally, so a directory holding `init.luau` is that script with its siblings as children, and `.client` / `.server` / `.legacy` suffixes pick the script class). `.vscode/generate-sourcemap.ps1` applies the same rules to produce `sourcemap.json` for the Luau Language Server, so the gate works with Studio closed. Script Sync also writes its own `sourcemap.json` (absolute paths) whenever it syncs; the two are interchangeable for luau-lsp, and neither is edited by hand or committed.

`StarterCharacterScripts` and `StarterPlayerScripts` live at the repository root and are mapped under `StarterPlayer`.

- `ReplicatedStorage/Client.client.luau` is the client bootstrap. It loads `CmdrClient` when present, registers every direct child module of `ReplicatedStorage/Handlers` with Crystal, then calls `Crystal.Run()`.
- `ServerScriptService/Server.legacy.luau` is the server bootstrap. It registers Cmdr hooks, types, and commands from `ServerScriptService/Cmdr`, registers every direct child module of `ServerScriptService/Handlers` with Crystal, then calls `Crystal.Run()`.
- `ReplicatedStorage/Handlers` contains client handlers. `ServerScriptService/Handlers` contains server handlers. Crystal loads a handler only when it is a direct `ModuleScript` child of those folders; nested modules are required by their handler.
- `ReplicatedStorage/Shared` contains code and data safe to require from either runtime: Crystal, the bus, configs, UI, shared gameplay views, and utility libraries.
- `ReplicatedStorage/Shared/Libs` holds `Logger` and `StateMachine` (project code) next to vendored third-party libraries: `Packet`, `PartCache`, `Ripple`, and `Signal`. The vendored ones are committed as-is and excluded from lint and type analysis.
- `ServerScriptService/Cmdr` contains Studio/admin command definitions. The client command surface is `ReplicatedStorage/CmdrClient`, created by Cmdr at runtime.

## Authored assets

Everything authored (no scripts) ships as Roblox Packages (`PackageLink`) and lives only in the place, not on disk: `Workspace.World` (bakeries, environment, roofs, spawn, and the `Assets` folder of 3D templates), `ReplicatedStorage.Assets` (prompt billboard, animations, models, VFX), and `StarterGui.MainGui` (every ScreenGui). Because a package is one instance, each of these adds a wrapping folder, and code addresses the contents relative to it:

- `ReplicatedStorage/Shared/World.luau` is the only place that knows the world package's location. `World.Root` / `WaitForRoot` find `Workspace.World`; `World.Bakeries`, `World.Assets`, and `World.Find(path)` resolve below it. Configs that name world content (`Base.BakeriesFolderName`, `Traffic.RoadPath`, `Traffic.Signals.Path`, `Guests.Street.SidewalkPath`) are child-name paths relative to that root, never to `Workspace`. Templates that are cloned rather than placed (building models, food, tools, the traffic vehicle variants in `Traffic.VehiclesFolder`) live under `ReplicatedStorage.Assets.Models`, not in the world. Anything else the game needs from the world must go through this module rather than `workspace:FindFirstChild`.
- `UIHandler` waits for `PlayerGui.MainGui` (`SCREENS_FOLDER`) and hands that folder to `Shared/UI/App` as the root that all screens are looked up under. Nothing else looks up an authored screen by name in `PlayerGui`; drivers go through `UIHandler:GetPanel` / `GetHud`.
- `ReplicatedStorage.Assets.VFX` holds one flat `BasePart` per effect named in `Configs/VFX.Effects` (plus `OvenFire`), carrying the emitters and the placement attributes `VFXHandler` reads (`SourceOffset`, `SourceFoodSize`, `SourceToolSize`, `BodyOffset`). These parts were extracted from the artists' staging rigs (the `SourcePath` attribute records where); the rigs themselves are not part of the place. Author a new effect by adding a part here and a row in `VFX.Effects`, never by shipping a rig.
- `StarterGui.ResetPlayerGuiOnSpawn` is `false` in the place. Every screen was already `ResetOnSpawn = false` and is bound once by the client, but a Folder in `StarterGui` has no such property: with the default setting Roblox destroys and re-copies the whole `MainGui` folder on respawn, which leaves the client holding dead screens. The place-level setting keeps `PlayerGui` intact across respawns. Do not turn it back on.

## Dependencies

Wally owns every registry package. `ReplicatedStorage/wally.toml` lists the shared-realm packages (`cmdr`, `flux`, `janitor`, `topbar-plus`, `typed-promise`) and installs into `ReplicatedStorage/Packages`; `ServerStorage/wally.toml` lists the server-realm packages (`profilestore`) and installs into `ServerStorage/ServerPackages`. Both install directories are gitignored; the manifests and lock files are committed.

Run `scripts/install-packages.ps1` after cloning or changing a manifest. It rebuilds both trees with `wally install`, then flattens each package into the layout Script Sync understands: Wally emits Rojo projects (`_Index/<package>/<name>/default.project.json` pointing at `src/`, `lib/`, or one file), which Script Sync would mirror as a Folder and break every link `require`. The flatten step moves the mapped root up so `<name>/init.luau` is the package, drops non-script files, and renames `.lua` to `.luau` (what Script Sync writes back). It then regenerates the sourcemap and runs `wally-package-types` so the types a package exports (for example `Flux.Node`, `Janitor.Janitor`, `TopbarIcon.Icon`) are visible through the generated link files. Never run `wally install` on its own.

## Ownership boundaries

- The server is authoritative for persistent state, economy, purchases, inventory, plot and building mutations, customer simulation outcomes, and rewards. Client handlers present that state and send requests.
- Shared modules must not depend on client-only or server-only modules. Runtime-specific behavior belongs in `ReplicatedStorage/Handlers` or `ServerScriptService/Handlers`.
- `ReplicatedStorage/Shared/Configs` owns static tuning and registries. Do not duplicate those tables inside handlers. Registry entry types are declared as an authored `Definition` plus the `id` that `Registry.Build` stamps on every entry. Instance paths in configs are relative to the package root described under "Authored assets".
- `ReplicatedStorage/Shared/Bus.luau` is the in-process event boundary. Cross-network contracts stay explicit in the handler that owns the remote.
- Crystal owns handler startup order through each handler's `dependencies` and `priority`. A handler must declare the handlers it requires instead of reaching into another handler before `Crystal.Run()` finishes.
- Third-party code under `ReplicatedStorage/Packages`, `ServerStorage/ServerPackages`, and the vendored `Shared/Libs` entries above is not application code: fix call sites, not the libraries.

## Validation

- `rokit.toml` pins Selene, StyLua, luau-lsp, Wally, and wally-package-types. Run tools through Rokit from the repository root.
- `scripts/check.ps1` is the verification gate: it regenerates the sourcemap, runs `selene .`, then runs the pinned analyzer over every source root: `luau-lsp analyze --platform roblox --definitions <globalTypes.PluginSecurity.d.luau> --sourcemap sourcemap.json --settings .vscode/settings.json ReplicatedFirst ReplicatedStorage ServerScriptService ServerStorage StarterCharacterScripts StarterPlayerScripts`. The definitions file defaults to the one the luau-lsp editor extension downloads into its global storage (`%APPDATA%\Cursor\User\globalStorage\johnnymorganz.luau-lsp\`); pass `-Definitions` to use another copy.
- Analysis uses luau-lsp's default type solver, matching the editor. Two shared shims exist because of it: `BaseStats.StatKey` is an explicit key union (no `keyof`), and `Shared/UI/Scope.luau` wraps `Flux.scope` for callbacks that return nothing. Flux selectors (`Find.Path`, `Find.Child`) are given plain signatures where they are used.
- The editor runs Roblox's live FFlags while the CLI enables all stable flags, so the editor can be stricter about missing optional table fields. Config-style inputs therefore get their own input type (for example `StateMachine.StateDefinition`, the registry `Definition` types) rather than reusing the fully-populated runtime type.
- `.vscode/settings.json` and `selene.toml` exclude the Wally directories and the vendored libraries from diagnostics and lint. Project code must analyze cleanly with strict DataModel types; authored instances a module relies on are declared as an `AuthoredScreen`-style intersection type at the point of use.
- Formatting follows StyLua defaults; `.styluaignore` mirrors the lint exclusions. The `--[[ Section ]]--` header comments are rewritten by StyLua, so a repo-wide `stylua --check` is not part of the gate.
- The luau-lsp Studio companion plugin talks to the editor on port `3668` (`luau-lsp.studioPlugin.port`), shared with the other projects the Studio plugin is configured for, with `maximumRequestBodySize` raised to `50mb` because this place's DataModel dump exceeds the 3 MB default. Only one workspace can own the port at a time.
