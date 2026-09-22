# Repository instructions

When reviewing, creating, or modifying Luau code, you can read `ARCHITECTURE.md` before acting depending if it's needed, and follow its ownership and change boundaries. Update the `ARCHITECTURE.md` if you modify things by the end of your response.

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

`scripts/check.ps1` runs steps 1–3 with the correct arguments. A bare `luau-lsp analyze .` is not a valid check: without the definitions, sourcemap and settings it reports every Roblox global and `require` as unknown.

After changing a `wally.toml`, run `scripts/install-packages.ps1` (never a bare `wally install`): it also flattens the packages into the layout Studio's Script Sync expects and regenerates the sourcemap and link-file types.
