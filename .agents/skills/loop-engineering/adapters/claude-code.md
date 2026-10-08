# Adapter: Claude Code

Thin mapping only. The workflow is in `../SKILL.md`; project rules are in `../projects/`.

**Discovery.** Claude Code discovers skills at `.claude/skills/<name>/SKILL.md` (project) or
`~/.claude/skills/<name>/SKILL.md` (personal), matched by the `description` frontmatter. This repo keeps the
canonical copy in `.agents/skills/loop-engineering/`. To expose it to Claude Code, symlink rather than copy:

```bash
mkdir -p .claude/skills && ln -s ../../.agents/skills/loop-engineering .claude/skills/loop-engineering
```

If your setup cannot follow symlinks, copy the folder and re-copy after every change to the canonical one
(see "Keeping in sync" in `../tests/scenarios.md`). **(verify)** the discovery path against the Claude Code
version in use before relying on it.

| Loop need | Claude Code tool |
|---|---|
| Read docs and code | `Read`, `Grep`, `Glob` |
| Edit | `Edit` (prefer over rewriting files), `Write` for new files |
| Run tests / lab scripts | `Bash` (set a timeout; long labs run in the background) |
| Track phases | `TodoWrite` - one item per acceptance criterion |
| Delegate | `Task` subagent for read-only research or an independent VERIFY re-run. Give it the criteria, not your conclusions |
| Ask the human | ask directly in the reply and stop; do not continue on a guess |

Notes
- Run VERIFY commands yourself after the last edit, even if a subagent claims it did.
- Permission prompts count as approval only for the exact action shown, not for the approval list in the profile.
