# CODE_STYLE.md — cake-game

Luau style for new and changed application code. Read [AGENTS.md](AGENTS.md) and [ARCHITECTURE.md](ARCHITECTURE.md) for runtime ownership. This guide adapts the supplied Template's structure to the actual Crystal/Packet/Flux repository. Do not mass-convert existing code or dependencies.

## Structure and names

- Start new application modules with `--!strict`; annotate named function parameters and returns. Preserve existing typed contracts when modifying older nonstrict framework/data files; do not turn a focused edit into a strictness migration. Never remove strict checking or add broad diagnostic suppression to hide errors.
- Use tabs, double-quoted strings, trailing commas in multiline tables, a final newline, and no trailing whitespace. Follow StyLua defaults and adjacent code. Avoid whole-file formatting churn; section comments can be rewritten by StyLua.
- Use PascalCase for module/type names and public methods, UPPER_SNAKE_CASE for constants, and descriptive camelCase for parameters and function-local variables. Keep nearby private helper/field naming; do not import the Template's snakeCase locals or new `T_` prefixes into existing modules.
- Folder references commonly use `_Shared`, `_Configs`, `_Handlers`, `_Packages`. Require package links by their actual lowercase/hyphenated names, such as `_Packages.janitor` and `_Packages["typed-promise"]`.
- Group services, references, requires, types/constants/state, module table, helpers, and public methods; return the module last. Preserve existing `--[[ Services ]]--`, `--[[ Modules ]]--`, and similar section landmarks. Omit empty sections.
- Cache services/references at module scope when available there. Private children of an `init.luau` module are `script.Child`, not `script.Parent.Child`.

## Function and module design

- Keep one responsibility per module. Use plain functions for stateless helpers, Crystal handlers for runtime systems, and factory/class objects for entities with independent state and teardown. Prefer composition; do not add framework layers for small tasks.
- Prefer early returns and `continue` to deeply nested branches. Aim for at most three indentation levels in function bodies; extract a meaningful helper when nesting hides intent. Keep multiline guards consistent with neighboring code and StyLua.
- Prefer direct table iteration and Luau conditional expressions. Use explicit nil comparisons when `false` or absence matters. Avoid `condition and value or fallback` when `value` can be false/nil.
- Use `task.spawn`, `task.delay`, and `task.wait`, not legacy `spawn`, `delay`, or `wait`. Own/cancel background work; startup callbacks must return.
- Write explanatory comments for invariants, sync behavior, and non-obvious decisions. Prefer named constants/configs over unexplained tuning numbers.

## Crystal handler shape

This is a structural example, not a new file to install:

```lua
--!strict

--[[ Tables ]]--
local ExampleHandler = {
	dependencies = {},
	priority = 0,
}

--[[ Handling ]]--
function ExampleHandler.OnInit(_self: ExampleHandler): ()
	-- Initialize local state here.
end

function ExampleHandler.OnStart(_self: ExampleHandler): ()
	-- Connect owned behavior here; return instead of running a permanent loop.
end

export type ExampleHandler = typeof(ExampleHandler)

return ExampleHandler
```

Follow a nearby handler's explicit `self` typing when it has mutable state. Declare actual dependencies before using another handler. Registered names can differ from filenames: `DataHandlerClient` declares `name = "DataClient"`. Crystal proxies ordinary methods for middleware; `OnInit` and `OnStart` remain plain lifecycle functions. Do not call lifecycle methods manually.

## Types and validation

- Share reusable gameplay contracts through existing modules such as `Shared/GameTypes`; keep local implementation types local. Use `T?` for optional values and exported types for public contracts.
- Prefer inference for obvious values and contextual callbacks. Isolate unavoidable `any` at dynamic network, proxy, or third-party boundaries; validate/narrow before use. A cast is not runtime validation.
- Keep authored input definitions separate from enriched runtime records, following registry `Definition` types and `Registry.Build`. Preserve existing default-solver shims such as `BaseStats.StatKey` and `Shared/UI/Scope`.
- Use legitimate `typeof`, `IsA`, `FindFirstChild`, and `WaitForChild` checks for untrusted inputs, optional assets, and replication. Choose timeouts/failure behavior from the actual lifecycle; do not apply an arbitrary global timeout or silently skip required state.
- Validate remote values and server authorization before state changes. Extend `Shared/Bus` and the owning handler together. Follow [AGENTS.md](AGENTS.md) for proxy-safe mutation and receipt handling.

## UI, ownership, and logging

- Bind authored `MainGui` screens with existing Flux nodes, `Shared/UI/App`, and UI helpers. Screen drivers use `UIHandler`; client data comes through `DataClient` readiness/read/subscribe APIs.
- Use the existing motion abstraction for the surface: `Shared/UI/Motion` for Flux springs, `Shared/UI/Animate` for existing Ripple-driven effects. Do not replace one globally because another is installed.
- A transient object/scope owns its connections, tasks, instances, and subscriptions. Reuse Janitor, Flux cleanup, or the surrounding explicit teardown contract. Make teardown safe for repeated cleanup and player/character removal.
- Use `Shared/Libs/Logger` with a module name when the subsystem uses it. Direct warnings should include `[ModuleName]`. Use backtick interpolation for readable messages; `string.format` remains appropriate for numeric formatting.
- Handle failures from `pcall`/promises according to the operation: propagate, log an actionable failure, or explicitly document the expected fallback. Do not hide required startup failures or leave noisy temporary prints.

## Verification

Every `.lua`/`.luau` addition, deletion, or modification requires the full `scripts/check.ps1` gate in [AGENTS.md](AGENTS.md), including regenerated sourcemap, Selene, and the Rokit-pinned Roblox-aware analyzer. Do not widen exclusions, weaken types, or claim success from editor diagnostics alone. Test changed runtime behavior in Studio when available.
