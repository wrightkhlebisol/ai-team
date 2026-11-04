Documents

- `process.md` - how work is organized (the agent team loop). Any change to
  code beyond a trivial fix goes through it by default; skip only when the
  user says so
- `_docs/team/*.md` - the role definitions; `.claude/agents/` wraps each as a
  subagent and `.claude/commands/` holds `/work-issue`, `/work-backlog`,
  `/plan-project`
- Before writing tests, read `_docs/testing-guidelines.md` if it exists
- For anything touching the UI, read the design system named in the
  project's Workspace config (default `_docs/design-system/`) if it exists

Using this team in another project: copy `process.md`, `_docs/` and
`.claude/agents/` + `.claude/commands/` (agents and commands must sit in the
project ROOT's `.claude/`), then add a "Workspace config" section to the
project's `CLAUDE.md` (see `process.md`).
