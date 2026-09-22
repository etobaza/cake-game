# AI instruction discovery — cake-game

`AGENTS.md` is the shared rule source. `ARCHITECTURE.md`, `CODE_STYLE.md`, and `PACKAGES.md` hold deeper project facts. A link to a document is an instruction to read it, not proof the host automatically injected its contents.

## Supported entry files

Open this repository as the workspace/project before starting a new conversation. The following behavior was checked against official documentation on 2026-09-22:

| Host | Entry used by this repository | Loading / verification |
| --- | --- | --- |
| Codex | Root `AGENTS.md` | Builds instructions at session startup from the Git root toward the working directory. Check for higher-priority `AGENTS.override.md` and the configured instruction-size limit. [Official docs](https://learn.chatgpt.com/docs/agent-configuration/agents-md). |
| Claude Code | Root `CLAUDE.md` importing `@AGENTS.md` | Imports expand at launch. Use `/memory` to inspect loaded files. [Official docs](https://code.claude.com/docs/en/memory). |
| Cursor Agent | Root `AGENTS.md` | Native project instructions; no duplicate `.cursor/rules` file needed. This does not configure Cursor Tab. [Official docs](https://cursor.com/docs/rules). |
| GitHub Copilot | `.github/copilot-instructions.md` | Repository instructions direct the agent to shared docs and include core checks. Inspect response references for the instruction file; feature/settings support varies. [Official docs](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions). |
| Gemini CLI | Root `GEMINI.md` importing `@./AGENTS.md` | Native context file/import. Use `/memory show` to see loaded content; `/memory reload` rescans it. [Official docs](https://geminicli.com/docs/cli/gemini-md/). |
| Zed Agent | `.github/copilot-instructions.md`, then its directive to read `AGENTS.md` | Zed picks the first supported project filename; Copilot instructions precede `AGENTS.md`. External/terminal agents use their own discovery rules. [Official docs](https://zed.dev/docs/ai/instructions). |

For an AI/chat product without repository instruction support, attach or explicitly provide these files. A normal browser chat with no repository access cannot discover local files automatically. Support is determined by the host application, not just the model name.

## Verification recorded on 2026-09-22

- **Codex desktop-bundled CLI `0.155.0-alpha.9.2`: passed.** A fresh ephemeral session in this repository, with a read-only sandbox and an explicit no-tools prompt, correctly identified all six expected facts below. Its event stream contained the answer and no tool calls. This verifies automatic root-rule loading for that binary/session, not automatic loading of every linked document or future compliance.
- **PATH Codex CLI `0.122.0`: incompatible with the current local configuration.** Startup rejected `service_tier = "default"`; a process-only `flex` override reached the service but was rejected there and also exposed newer model-metadata parsing incompatibilities. The successful test used the newer desktop binary without changing global configuration. This does not establish that the older terminal CLI works.
- **Claude Code `2.1.156`: live check blocked.** The fresh no-tools test returned `401 OAuth access token has expired`. Import syntax was checked statically against the official documentation; successful model ingestion remains unverified until authentication is restored.
- **Cursor, Copilot, Gemini CLI, and Zed:** entry-file behavior checked against official documentation; no fresh interactive session was exercised in these hosts. In particular, the Zed/Copilot directive to read supporting files still needs the read-access check below.
- **Repository checks passed:** local Markdown links, Claude/Gemini import targets, documented source paths, package pins versus both manifests, instruction size, Git ignore visibility, and whitespace/diff checks. No higher-priority root rule file or nested `AGENTS.override.md` was found. This change edits documentation only, so it did not run the Luau gate or Studio Play.

## New-session check

After editing instructions, start a fresh session in the repository. Resuming an old conversation can retain older instructions. For Codex CLI, launch from the root or use `--cd D:/Github/Rojo/cake-game`.

First, test automatic loading without giving the answer or asking the model to search files:

> Do not use tools or modify files. From repository instructions already loaded into this session, identify the project, startup callbacks, network contract path, proxy-list helper, required verification command, and documents required at session start. Say which details are missing instead of guessing.

Expected facts: cake-game; Crystal `OnInit` / `OnStart`; `ReplicatedStorage/Shared/Bus.luau`; `Shared/DataList`; `scripts/check.ps1`; `AGENTS.md` and `ARCHITECTURE.md`, plus `CODE_STYLE.md` before Luau and `PACKAGES.md` before dependency changes. A short pointer entry such as Copilot/Zed may need the next read step to retrieve every detail.

Then verify instruction-following with read access:

> Read the documents required by the repository startup rules. Name the loaded files, explain what to do before and after a Luau edit, and identify the startup, network, and persistence owners. Do not modify files or start Studio Play.

The read step should load the applicable supporting documents, preserve existing edits, and identify the full gate: sourcemap regeneration, Selene, and full-project analysis with Roblox definitions, settings, and the Rokit-pinned analyzer. Pair the answer with the host's instruction/context references or file-read trace when available. A correct answer alone does not prove every future response will follow every rule.

## Troubleshooting and maintenance

- Codex: the first nonempty global `AGENTS.override.md` / `AGENTS.md` supplies personal rules. At each project directory, `AGENTS.override.md` takes precedence over `AGENTS.md`; nested instructions may override root guidance. The documented default combined project-instruction budget is 32 KiB. Keep the main rules compact.
- Claude/Gemini: preserve the native import line outside code fences. A plain Markdown link is not the same as an import. Check host settings that exclude or rename memory/context files.
- Zed: `.rules`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, and `AGENT.md` precede `AGENTS.md`. Do not introduce an unrelated earlier entry that silently replaces this project's guidance.
- Copilot: ensure custom instructions are enabled for the feature in use and the repository is attached/open. Cloud agents only see repository files available in their checkout; uncommitted local files do not travel automatically.
- Keep these files in Git. No symlinks, absolute imports, or local editor settings are needed for the shared rules. The optional local Roblox skill path is workstation-specific; the project contract is documented in the repository itself.
- Rule loading supplies context; it is not enforcement. Required CLI checks provide executable verification for code, while fresh-chat checks detect discovery/configuration problems.
