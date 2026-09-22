# cake-game repository instructions

Read and follow [AGENTS.md](../AGENTS.md) before project work and [ARCHITECTURE.md](../ARCHITECTURE.md) for ownership. Read [CODE_STYLE.md](../CODE_STYLE.md) before reviewing or writing Luau and [PACKAGES.md](../PACKAGES.md) before changing dependency usage. These repository files are authoritative; do not create a separate Copilot rule set.

This Roblox project uses Studio Script Sync, Crystal handlers with `OnInit`/`OnStart`, Packet contracts in `ReplicatedStorage/Shared/Bus.luau`, Wally dependencies, and Flux-driven authored UI. Preserve server authority, DataHandler proxy mutation, and PurchaseHandler receipt deduplication. Preserve existing user edits.

All first-party Luau must start with `--!strict`; never use `--!nonstrict` or `--!nocheck`. After any `.lua` or `.luau` change, run `scripts/check.ps1` from the repository root. It must regenerate the sourcemap and pass Selene, the `--!strict` header check, and full-project Roblox-aware analysis using the Rokit-pinned luau-lsp. After a `wally.toml` change, use `scripts/install-packages.ps1`, never bare `wally install`. Update architecture documentation when contracts change and distinguish static checks from Studio tests.
