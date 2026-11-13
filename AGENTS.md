This repo is the `ai-team` Claude Code plugin (and its own marketplace).

- `.claude-plugin/plugin.json`: the manifest. Bump `version` on every change
  users should pick up
- `.claude-plugin/marketplace.json`: lists this repo's root as the one plugin
- `agents/*.md`: one subagent per role. The body is the full role definition;
  keep it generic (no project names, stacks or paths). Project rules belong in
  the using project's "Agent team notes"
- `commands/*.md`: `/ai-team:work-issue`, `/ai-team:work-backlog`,
  `/ai-team:plan-project`, `/ai-team:plan-go-to-market`
- `skills/team-process/SKILL.md`: the orchestrator loop; `po.md` beside it is
  the Product Owner guide

Check changes with `claude plugin validate .`, and try them in a project with
`claude --plugin-dir <path to this repo>`.
