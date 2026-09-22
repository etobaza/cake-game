# AGENTS.md — cake-game

Shared operating rules for coding agents working in this repository. Keep project rules here; tool-specific entry files point here instead of maintaining separate copies. Explicit user instructions take precedence over repository conventions.

## Start every new session

1. Read this file and [ARCHITECTURE.md](ARCHITECTURE.md) before project work. Read [CODE_STYLE.md](CODE_STYLE.md) before reviewing or writing Luau. Read [PACKAGES.md](PACKAGES.md) before changing dependency usage.
2. Load the installed `roblox` skill for Roblox/Luau work. If unavailable through the skill catalog, this workstation's fallback is `C:/Users/z1vas/.codex/skills/roblox/SKILL.md`. On another machine, use the repository docs and report a missing skill without pretending it loaded.
3. Inspect `git status --short`; preserve existing user changes. Read the relevant handler and a nearby implementation. Discover available Studio tools when runtime inspection is needed; do not assume a connection, place, or tool name.
4. Follow these rules throughout the session. After compaction, reload any required instructions no longer in context. For multi-file changes, briefly describe the affected owners before editing.
5. For Lemon Cake reference questions or parity work, read [mem/lemon-cake.md](mem/lemon-cake.md), then follow its links into [Exeperience/LemonCake](Exeperience/LemonCake/README.md). Keep installed-build evidence separate from cake-game adaptations and untested runtime claims.

Keep user-facing replies brief. Use the installed `caveman` skill at `ultra` intensity when available, unless the user says `stop caveman` or `normal mode`. Keep code, durable documentation, commits, PRs, and safety-critical steps in clear normal prose.

## Project contract

This is an existing Roblox bakery game, not a blank template. Disk folders mirror DataModel services through Studio Script Sync. Wally manages dependencies; Rokit pins CLI tools. The repository location does not imply a Rojo build workflow.

| Owner | Location / contract |
| --- | --- |
| Server bootstrap | `ServerScriptService/Server.legacy.luau` |
| Client bootstrap | `ReplicatedStorage/Client.client.luau` |
| Server systems | Direct ModuleScript children of `ServerScriptService/Handlers` |
| Client systems | Direct ModuleScript children of `ReplicatedStorage/Handlers` |
| Startup | `ReplicatedStorage/Shared/Crystal.luau`: register handlers, then `Crystal.Run()` |
| Shared logic / tuning | `ReplicatedStorage/Shared`, especially `Configs` and `Configs/Registries` |
| Network contracts | `ReplicatedStorage/Shared/Bus.luau`, built with `Shared/Libs/Packet` |
| Persistence / client mirror | Server `DataHandler`; client `DataHandlerClient` (registered name `DataClient`) |
| Authored UI | Place-only `StarterGui.MainGui`, mounted by `UIHandler` and `Shared/UI/App` |
| Authored world | Place-only `Workspace.World`, resolved through `Shared/World.luau` |

- Add systems as handlers, not a second bootstrap. Existing support modules such as `TutorialEvents` and `ProgressReset` are not evidence of another loader. Crystal scans direct children only; private modules belong beneath their handler and are required explicitly.
- Use `OnInit` / `OnStart`, not the reference template's `Init` / `Start`. Declare required handler **registered names** in `dependencies`. Higher `priority` orders ready handlers; it does not replace dependencies.
- Crystal runs all `OnInit` calls before `OnStart`; both phases execute in dependency order. `OnStart` is awaited, not spawned. Keep initialization local; wire other handlers in `OnStart`. Launch owned background loops instead of blocking startup forever.
- Keep server-only state, reward decisions, purchases, inventory, customer outcomes, and world mutations on the server. Shared code must not require server-only modules or assume a client context at require time.
- Put tuning in existing configs and registries. Preserve stable IDs, relative asset paths, and exported type contracts. Do not import another project's loader, services, ByteNet, Charm, or anti-cheat subsystem as an incidental change.

## Data, networking, and cleanup

- Define cross-network contracts once in `Shared/Bus.luau` with the existing Packet API; implement validation and behavior in the owning handler. `Shared/Libs/Signal` is for in-process events.
- The server validates client intent before mutation: types, finite/ranged numbers, identifiers, ownership, distance, readiness, and appropriate rate/cooldown checks. Reuse `Shared/Sanitize` where it fits; it is not a complete authorization or rate-limiting system. Never accept client prices, rewards, or completion claims as truth.
- Mutate `DataHandler` data through its proxies. Use `Shared/DataList` for proxied lists. `table.insert`, `table.remove`, `table.find`, `table.clone`, raw writes, or writes through `GetOriginalTable` bypass proxy behavior. Original-table access is for reads/copies inside the established API.
- Preserve ProfileStore store names, session keys, schema compatibility, migrations, and snapshot/revision behavior. Cloud and Session templates live under `ReplicatedStorage/Handlers/DataHandlerClient/Config`; they are replicated, so they must contain no secrets.
- `PurchaseHandler` owns `MarketplaceService.ProcessReceipt`. Preserve durable receipt deduplication and reward idempotency. Do not introduce another receipt callback or an alternate direct DataStore write path.
- Check saving configuration before runtime persistence tests: Studio can save real data here. Do not reset profiles, change store identity, publish, or test real purchases as a routine verification step.
- Give temporary connections, tasks, models, animation tracks, and subscriptions an owner and cleanup. Use existing Janitor, Flux scopes, or explicit established teardown. Process-lifetime handler connections may share the handler lifetime.

## Studio, UI, and dependencies

- Edit disk-backed source on disk. Allow Script Sync lag; do not create, rename, or reparent a second disk-backed instance through Studio. Avoid incidental file-to-folder conversions at the same synced path.
- A directory containing `init.luau` becomes the module; its other scripts are children, accessed with `script.Child`. Preserve existing `.client`, `.server`, and `.legacy` suffix conventions and sourcemap mappings.
- Inspect the active place and authored hierarchy before asset changes. Models, GUI, animations, and VFX are not fully described by the scripts-only filesystem.
- Drive authored screens through `UIHandler:GetPanel` / `GetHud` and existing Flux/UI helpers. Preserve `StarterGui.ResetPlayerGuiOnSpawn = false`. Existing generated overlays/previews are valid; do not rebuild authored screens in code.
- Resolve world content through `Shared/World.luau`; clone model templates from `ReplicatedStorage.Assets.Models`. Keep configured world paths relative to `Workspace.World`.
- Do not edit generated Wally packages or vendored `Shared/Libs/{Packet,PartCache,Ripple,Signal}`. `Logger` and `StateMachine` in the same folder are project-owned.
- After changing either `wally.toml`, run `scripts/install-packages.ps1`, never bare `wally install`. It installs, flattens packages for Script Sync, regenerates the sourcemap, and fixes package link types. Keep manifests and lock files together; do not hand-edit generated links.

## Strict Luau (mandatory)

- Every first-party `.lua` / `.luau` file must begin with `--!strict` on line 1, new files included. Only generated Wally packages and the vendored `Shared/Libs/{Packet,PartCache,Ripple,Signal}` are exempt; `scripts/check.ps1` rejects any other file without the header.
- Never use `--!nonstrict` or `--!nocheck`, remove or move the directive, or widen `luau-lsp.ignoreGlobs` to escape analysis. Fix type errors instead of silencing them; cast to `any` only at a genuinely dynamic boundary, as narrowly as [CODE_STYLE.md](CODE_STYLE.md) describes.

## Required Luau verification

After adding, removing, or modifying any `.lua` or `.luau` file:

1. Regenerate `sourcemap.json` using `.vscode/generate-sourcemap.ps1`.
2. Run `selene .`.
3. Run `luau-lsp analyze` against every `.lua` and `.luau` file, passing:
   - `--platform roblox`
   - the Roblox definitions file
   - `--sourcemap sourcemap.json`
   - `--settings .vscode/settings.json`
4. The analyzer must use the project-pinned Rokit binary. Do not rely only on VS Code Problems or diagnostics from opened files.
5. Do not report completion until both Selene and full-project type analysis exit successfully.
6. If the editor reports an error that the CLI does not, compare the editor and CLI `luau-lsp` versions and reproduce the check using the editor’s exact version.

`scripts/check.ps1` runs steps 1–3 with the correct arguments and also fails when a first-party module does not start with `--!strict`. A bare `luau-lsp analyze .` is not a valid check: without the definitions, sourcemap and settings it reports every Roblox global and `require` as unknown.

After changing a `wally.toml`, run `scripts/install-packages.ps1` (never a bare `wally install`): it also flattens the packages into the layout Studio's Script Sync expects and regenerates the sourcemap and link-file types.

Run the gate from the repository root. Use `scripts/check.ps1 -Definitions <path>` when definitions cannot be resolved automatically. Restore tools with `rokit install` when needed; do not substitute an unrelated analyzer from PATH. If a required check cannot run or fails, report the exact blocker and do not claim verified completion.

For gameplay/UI changes, also restart Studio Play after source sync, inspect server/client errors, and exercise the changed behavior when Studio tools are available. A boot log alone is not a feature test. If Studio is unavailable, state the pending runtime scenario. Documentation-only changes need link, path, consistency, and diff checks; no Play session or Luau gate is required unless source also changes.

## Finish and maintain

- Keep edits within the requested feature/fix; do not reformat or rename unrelated code to match the new guide.
- Update `ARCHITECTURE.md` when modifying project behavior, layout, tooling, or rules. Update `CODE_STYLE.md` / `PACKAGES.md` when their contracts change. Keep AI entry files as pointers/imports, and avoid conflicting copies of the rules.
- Report what changed, what was actually checked, and any remaining verification limits. Never label static inspection as a Studio test.
- [AI_INSTRUCTIONS.md](AI_INSTRUCTIONS.md) documents supported AI discovery, overrides, and a repeatable new-chat verification procedure. Instruction loading is not a guarantee of perfect model compliance.
