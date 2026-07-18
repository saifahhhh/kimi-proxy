# Vault Templates — How to use

These templates are the starting scaffold of the "external brain" (external memory) that kimi_proxy reads/writes.

## Place templates into the vault

```sh
# Set VAULT_PATH to your vault (e.g. ~/brain)
export VAULT_PATH="$HOME/brain"
mkdir -p "$VAULT_PATH"
cp -r obsidian_templates/* "$VAULT_PATH/"
```

Resulting structure:

```
$VAULT_PATH/
├── _INDEX.md             ← Map of Content (regenerated automatically after writing notes)
├── project/
│   ├── architecture.md   ← edit to match your real project (priority 1)
│   ├── conventions.md    ← edit to match your real style (priority 1)
│   └── glossary.md       ← project-specific terms (priority 3)
├── tasks/
│   └── current.md        ← Planner overwrites when there is a new plan
└── decisions/
    └── _TEMPLATE.md      ← copy to use as ADR template (files starting with `_` are not indexed)
```

## Things you must do before using
1. Edit `project/architecture.md` + `project/conventions.md` to match your project
   (currently placeholder `<...>` waiting to be filled) — these two files are priority 1, loaded into context almost every time
2. Set `VAULT_PATH` so the proxy knows where the vault is
3. Don't delete `decisions/_TEMPLATE.md` — it's the ADR template

## Notes
- `_INDEX.md` is regenerated automatically after writing notes (see spec §11) — manual edits allowed but will be overwritten
- `sessions/` is not in the template — proxy creates it on first log append (append-only)
- Files whose basename starts with `_` (e.g. `_INDEX.md`, `_TEMPLATE.md`) and everything in `sessions/`
  are skipped during scan/indexing
