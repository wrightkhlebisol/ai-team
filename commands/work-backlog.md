---
description: Work open issues through the agent team loop in pipelined waves (groom/design ahead, independent builds in parallel worktrees)
argument-hint: [--auto] [label-or-milestone filter]
---

You are the orchestrator. Load the `ai-team:team-process` skill and read the
"Workspace config" and "Agent team notes" in the root `CLAUDE.md` now.
Arguments: $ARGUMENTS

1. List open issues on the tracker (`gh issue list -R <tracker> --state open`),
   applying any filter given. Skip issues labelled `needs-human` or
   `ready-for-review`; resume `in-progress` ones from their labels and comments
2. Groom every ungroomed issue up front, in parallel (PM subagents, a few
   issues each). Then launch the designer for each groomed UI issue whose
   design-system dependency is in place
3. Plan waves from the "Depends on" lines (see Pipelining in the skill):
   a wave is the issues whose dependencies are merged or have a branch in
   flight, minus any that would edit the same files as another build in the
   wave. Show the user the waves and confirm, unless `--auto`
4. Run each issue through the lifecycle as `/ai-team:work-issue` does, with
   the builds of a wave running at the same time, each in its own worktree,
   as many at once as `capacity.sh` admits (see Resource budget in the
   skill); queue the rest.
   As soon as an issue frees up (PR opened, or `needs-human`), start the next
   ready issue instead of waiting for the whole wave
5. When an issue hits `needs-human`, leave it, keep the rest moving, and hold
   back only the issues that depend on it
6. End with a table: issue, outcome (PR link / needs-human + reason / skipped),
   and for stacked PRs the branch each one targets
