# Adapter: Arena.ai Agent Mode

Thin mapping only. Workflow: `../SKILL.md`. Project rules: `../projects/`.

**Discovery.** No automatic skill loading is assumed. Start by reading
`.agents/skills/loop-engineering/SKILL.md` and `projects/forex-strategy-validation.md`.

| Loop need | Tool |
|---|---|
| Read | `read_file`; `bash` for `git`, `rg`, `ls` |
| Edit | `edit_file` for changes, `write_file` for new files |
| Run tests / labs | `bash` (default timeout 30 s; raise it, max 1800 s). Long jobs: `start_process` then `get_process_output` |
| Preview servers | `start_process` binding `0.0.0.0` (not needed for validation work) |
| Ask the human | `ask_user` for choices; otherwise ask in the reply |
| GitHub | `git` and `gh`, already authenticated. Never ask for tokens |

Environment facts worth knowing
- The session is pinned to one branch. Commit and push only there; never create or switch branches.
- The sandbox blocks Azure blob storage. `gh run download` and artifact zips fail with a TLS reset; use
  `codeload.github.com` for the `data/m5-history` branch (commands in the profile, section 4).
- The clone may be shallow. If `git merge` says "unrelated histories", run `git fetch --unshallow origin main`.
- Python packages: use `/tmp/venv` (system pip is externally managed). `/tmp` does not persist between
  sessions - recreate the venv and re-extract data each time.
