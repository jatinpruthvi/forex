# Adapter: Codex CLI, Gemini CLI, Copilot CLI

Thin mapping only. Workflow: `../SKILL.md`. Project rules: `../projects/`.

**Discovery.** This repo's own `writing-skills` guidance notes that Codex, Copilot CLI and Gemini CLI recognize
`~/.agents/skills/` as a cross-runtime alias, and this repo already stores skills under `.agents/skills/`. Put no
second copy anywhere: the canonical folder is `.agents/skills/loop-engineering/`. **(verify)** each CLI's
current discovery rules; if one only reads a global directory, symlink that directory to this folder.

If a CLI does not auto-load skills, start the session with:
"Read `.agents/skills/loop-engineering/SKILL.md` and `projects/forex-strategy-validation.md`, then follow them."

| Loop need | Typical equivalent |
|---|---|
| Read / search | shell (`cat`, `rg`, `git grep`) or the CLI's file reader |
| Edit | the CLI's patch/edit tool; avoid whole-file rewrites of large files |
| Run tests | shell; respect the sandbox and approval mode of the CLI |
| Delegate | sub-agents if available; otherwise run independent VERIFY yourself in a fresh shell |
| Ask the human | stop and ask; in non-interactive mode, end with status BLOCKED and the exact question |

Notes
- In a read-only or no-network sandbox, VERIFY may be impossible. Report BLOCKED with what could not run.
  Do not downgrade to "reviewed the code".
- Non-interactive runs must never assume approval. Anything on the profile's approval list becomes BLOCKED.
