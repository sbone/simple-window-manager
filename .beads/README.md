# Beads in this repository

Use `bd` for tasks and `bd remember` for persistent project knowledge.
[AGENTS.md](../AGENTS.md) defines the repository workflow; the project uses Codex.

```sh
bd prime                 # Load workflow context
bd ready                 # Find available work
bd show <id>             # Read a task
bd update <id> --claim    # Claim it
bd close <id>            # Close completed work
```

Issues live in the local Dolt database, not in source-code Git commits.
Cross-machine sync uses `bd dolt push` / `bd dolt pull` over the configured Git
remote under `refs/dolt/data`. Run remote sync only when explicitly requested.
A normal `git push` does not replace issue-data sync.

JSONL auto-export is disabled because Codex uses the `bd` CLI directly.
An existing `.beads/issues.jsonl` is an ignored, potentially stale export;
it is neither the source of truth nor a backup. Do not import it during
normal operation. Preserve the database and metadata when cleaning up.

## Setup maintenance

Codex uses `.agents/skills/beads/`, `.codex/hooks.json` and `AGENTS.md`.
Check installation with `bd setup codex --check`. If repairs are needed,
`bd setup codex` refreshes that integration; review its changes afterward.
The Git hook shims in `.beads/hooks/` are separate from Codex's context hooks.
Check their installation with `bd hooks list`.

Beads 1.3.1's `bd init` automatically stages and commits setup files and
installs Claude, Codex and Cursor integrations by default. This repository is
already initialized; do not rerun init as a routine repair. The
[init implementation](https://github.com/gastownhall/beads/blob/v1.3.1/cmd/bd/init.go)
explains the bootstrap commit. Disabling Dolt auto-commit does not disable
that source-code Git commit.
