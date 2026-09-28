# .skills — Vendored AI Skill Libraries

Skill content vendored from public third-party repos for use by AI coding agents
(Claude Code, Cursor, etc.). Only skill definitions + README/LICENSE are vendored;
upstream build tooling, tests, demos, and per-agent config dirs were dropped to keep
the repo lean (~16MB vs ~80MB full clones).

Originals are kept at `/tmp/skills-originals/` on this machine for future re-sync.

## Skill selection (how agents should use this library)

`INDEX.md` in this directory is the **router**. It is generated — never edit by hand:

```bash
pnpm skills:index          # regenerate .agents/skills/INDEX.md
pnpm skills:index:check    # exit 1 when the committed index is stale
```

Agents route through it: read `INDEX.md` → start from the **Daily shortlist**
(skills curated for this repo's stack: Next.js 16, React 19, Prisma + PostGIS,
Playwright a11y, SEO) → `grep` the full tables when nothing fits → pick the best
match → read that skill's `SKILL.md` in full → say which skill was picked.
The mandatory wording lives in the root `AGENTS.md` ("Skill selection — do this
FIRST, every task").

Adding, renaming, or removing a skill under `.agents/skills/` requires rerunning
`pnpm skills:index` in the same change, so the committed index never lies.

## Contents

| Directory | Source | Vendored |
|---|---|---|
| `genjutsu/` | https://github.com/AThevon/genjutsu | `skills/`, README, LICENSE |
| `gsap-skills/` | https://github.com/greensock/gsap-skills | `skills/`, README, LICENSE |
| `impeccable/` | https://github.com/pbakaus/impeccable | `skill/`, README, LICENSE, NOTICE |
| `motion-design-skill/` | https://github.com/lottiefiles/motion-design-skill | `skills/`, README, LICENSE |
| `skills/` | https://github.com/emilkowalski/skills | `skills/`, README, LICENSE |
| `superpowers/` | https://github.com/obra/superpowers | `skills/`, README, LICENSE |
| `taste-skill/` | https://github.com/Leonxlnx/taste-skill | `skills/`, README, LICENSE |
| `threejs-skills/` | https://github.com/cloudai-x/threejs-skills | `skills/`, README |
| `ui-ux-pro-max-skill/` | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill | `.claude/`, `.claude-plugin/` |

## Updating

Re-clone the upstream repo, copy the same paths listed above into the matching
directory here, and commit. Do not add the upstream `.git` folders.
