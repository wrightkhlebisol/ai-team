# ai-team

A Claude Code plugin that runs GitHub-issue-driven work through an agent team.
The main session is the orchestrator. It launches a PM, product designer,
software engineer, QA engineer and code reviewer as subagents, and stops at
two checkpoints for your approval (the plan, and before the PR).

## Install

```
/plugin marketplace add wrightkhlebisol/ai-team
/plugin install ai-team@ai-team
```

To turn it on for everyone working in a repo, commit this to the repo's
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "ai-team": { "source": { "source": "github", "repo": "wrightkhlebisol/ai-team" } }
  },
  "enabledPlugins": { "ai-team@ai-team": true }
}
```

## Use

```
/ai-team:plan-project              shape a feature with the PO and file issues
/ai-team:work-issue 42             run issue #42 through the loop, with checkpoints
/ai-team:work-backlog              work open issues in pipelined waves, with checkpoints
/ai-team:work-backlog --auto       same, without the two checkpoints
"skip the process, just fix X"     do a change directly, outside the loop
```

Plain-word requests to change code ("add X to the settings page") also run
through the loop, via the `team-process` skill.

## Set up a project

Add a **Workspace config** section to the project's root `CLAUDE.md`: repos,
base branch, worktree root, shared environments, issue tracker, design system,
test environment. The full list and the defaults are in
[`skills/team-process/SKILL.md`](skills/team-process/SKILL.md#workspace-config).

Optionally add an **Agent team notes** section with a `### <role>` heading per
role for project rules the generic agents can't know: the authz helper a
reviewer must look for, where the screens live, how money is stored.

## What's in the plugin

| Path | What |
| --- | --- |
| `agents/` | the five role subagents (`ai-team:pm`, `ai-team:product-designer`, `ai-team:software-engineer`, `ai-team:qa-engineer`, `ai-team:code-reviewer`) |
| `commands/` | `work-issue`, `work-backlog`, `plan-project` |
| `skills/team-process/` | the orchestrator loop (`SKILL.md`) and the Product Owner guide (`po.md`) |
