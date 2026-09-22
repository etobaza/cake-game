# PACKAGES.md — cake-game

Dependency map verified against repository manifests and call sites. These are source-inspection findings, not a claim that packages were smoke-tested in Studio for this documentation change. Read the installed API and a nearby call site before adding a new call.

## Installation and ownership

From the repository root, run `rokit install` for pinned tools and `scripts/install-packages.ps1` to restore packages. The script installs, flattens, validates, and generates exported link types in a temporary directory outside Script Sync, then replaces the watched package trees and regenerates the project sourcemap. This prevents raw package folders and development test runners from entering Studio during installation. With Studio open, verify the installed roots are ModuleScripts before restarting Play. Never run bare `wally install` or modify generated packages/links by hand.

| Wally link | Manifest pin | Use / reference |
| --- | --- | --- |
| `ReplicatedStorage.Packages.cmdr` | `evaera/cmdr@=1.12.0` | Server bootstrap registers `ServerScriptService/Cmdr`; client requires runtime `ReplicatedStorage.CmdrClient`. Preserve `Cmdr/Admin` and `Hooks/BeforeRun` authorization. |
| `ReplicatedStorage.Packages.flux` | `kohltastrophe/flux@=0.2.0` | Reactive UI nodes, bindings, scopes, springs. See `Handlers/UIHandler` and `Shared/UI/Motion`, `App`, `Scope`. |
| `ReplicatedStorage.Packages.janitor` | `howmanysmall/janitor@=1.18.3` | Transient resource ownership. See `Handlers/CharacterAnimationHandler/Character` and `Handlers/VFXHandler/Effect`. |
| `ReplicatedStorage.Packages["topbar-plus"]` | `1foreverhd/topbarplus@=3.4.0` | Topbar icons; see `Handlers/TopbarHandler`. |
| `ReplicatedStorage.Packages["typed-promise"]` | `howmanysmall/typed-promise@=4.0.6` | Promise-based async work; Crystal wraps startup with `Promise.promisify`. |
| `ServerStorage.ServerPackages.profilestore` | `lm-loleris/profilestore@=1.0.3` | Server-only persistence owned by `ServerScriptService/Handlers/DataHandler`. |

Pins above come from `ReplicatedStorage/wally.toml` and `ServerStorage/wally.toml`; manifests/lock files are authoritative. Install directories are ignored, while both manifests and lock files belong in Git.

## Committed libraries

Under `ReplicatedStorage/Shared/Libs`:

| Library | Ownership / use |
| --- | --- |
| `Packet` | Vendored networking serializer. `Shared/Bus.luau` declares named contracts used by both sides. Follow its `FireServer`, `FireClient`, and `OnServerEvent` call sites; do not substitute ByteNet APIs. |
| `Signal` | Vendored in-process signals, including DataHandler readiness/update events. Read this library's own constructor/types. |
| `Ripple` | Vendored motion library; used by `Shared/UI/Animate`. Reuse helper cleanup and existing presets. |
| `PartCache` | Vendored part pool. Presence is not a mandate to introduce pooling; inspect its API and existing usage first. |
| `Logger` | Project-owned logging utility; `LoggerUtil.new({ name = "HandlerName" })`. |
| `StateMachine` | Project-owned state machine; preserve `StateDefinition` input contracts. |

Vendored entries and generated Wally packages are excluded by lint/type settings. Fix application call sites instead of changing vendor code. `Logger` and `StateMachine` remain application code and require the normal Luau verification gate when edited.

## Integration rules

- Packet types describe transport, not authorization. Owning server handlers validate values and game rules; reuse `Shared/Sanitize` where applicable.
- ProfileStore is accessed through `DataHandler`'s existing proxy/readiness/save lifecycle. Use `Shared/DataList` for proxied arrays. Preserve store identity, schema reconciliation/migrations, and durable purchase deduplication.
- Cmdr creates/moves its client surface during server initialization. Do not require the server package from a client or rerun initialization in Edit mode to inspect it.
- Flux and Ripple coexist. Preserve the abstraction used by the touched UI surface, including cleanup through scopes/Janitor.
- The reference Template's ByteNet, Charm, Sift, Component, Zone, ObjectCache, Trove, and Symbol conventions are not this repository's dependency contract.
