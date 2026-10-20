# Agent setup (Claude Code + OpenCode)

One agnostic home for instructions and skills, thin bridges for each tool. This page is written so an agent can rebuild the layout on a new machine.

## Layout

```
~/.agents/                          single source of truth (tool-agnostic)
  AGENTS.md                         global instructions (real file)
  skills/<name>/SKILL.md            skills shared by every tool (real files)

~/.claude/                          Claude Code: bridges + Claude-only content
  CLAUDE.md                         one line: @AGENTS.md
  AGENTS.md                      -> ../.agents/AGENTS.md
  skills/<shared>                -> ../../.agents/skills/<shared>
  skills/<claude-only>/             real dirs, only for Claude-specific skills

~/.config/opencode/                 OpenCode: bridges + OpenCode-only content
  opencode.json                     models, agents, permissions, MCP
  AGENTS.md                      -> ../../.agents/AGENTS.md
  skills/<opencode-only>/           real dirs, only for OpenCode-specific skills
```

## Why this shape

- Claude Code reads only `~/.claude/CLAUDE.md` and `~/.claude/skills/`. It does not read `~/.agents/`, so it needs the symlinks.
- OpenCode reads `~/.config/opencode/AGENTS.md` and scans `~/.config/opencode/skills`, `~/.claude/skills` and `~/.agents/skills`. Skills are keyed by name, so one reachable from two places is listed once. On a name collision `~/.config/opencode/skills` wins over `~/.claude/skills`.
- A skill is shared only if it does not name tool-specific things (MCP tool names, `ToolSearch`, Code Mode). Skills that do get one real copy per tool, in that tool's own folder.

## Rebuild on a new machine

1. Restore or create `~/.agents/AGENTS.md` and `~/.agents/skills/` (from backup, or the migration archive).
2. Bridges for instructions:
   `mkdir -p ~/.claude ~/.config/opencode && printf '@AGENTS.md\n' > ~/.claude/CLAUDE.md && ln -sfn ../.agents/AGENTS.md ~/.claude/AGENTS.md && ln -sfn ../../.agents/AGENTS.md ~/.config/opencode/AGENTS.md`
3. Bridges for shared skills (idempotent, never overwrites a real dir):
   `mkdir -p ~/.claude/skills && for d in ~/.agents/skills/*/; do n=$(basename "$d"); [ -e ~/.claude/skills/$n ] || ln -s ../../.agents/skills/$n ~/.claude/skills/$n; done`
4. Put tool-specific skills in `~/.claude/skills/` or `~/.config/opencode/skills/` as real directories.
5. Restore `~/.config/opencode/opencode.json` (not in this repo: it holds company MCP endpoints).

## Verify

- `ls -la ~/.claude/AGENTS.md ~/.config/opencode/AGENTS.md` shows both symlinks resolving to `~/.agents/AGENTS.md`.
- `ls -la ~/.claude/skills | grep -- '->'` lists the shared skills.
- OpenCode: ask it to list its available skills; each shared skill appears once.
- Claude Code: `/skills` lists the same shared skills.

## Pitfalls

- A skill installer may write real copies into both `~/.claude/skills` and `~/.agents/skills`, or replace a symlink. After any skill install or update, rerun step 3 (after moving the stray real copy away if it is identical to the one in `~/.agents/skills`).
- Do not set `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`: it also hides Claude-managed skills (`~/.claude/skills/synced`) and per-project `.claude/skills` from OpenCode.
- Keep secrets out of `~/.agents`, `~/.claude/skills` and this repo.
