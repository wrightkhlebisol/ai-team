---
description: Run one GitHub issue through the agent team loop (groom → plan → design → build → QA → review → PR)
argument-hint: <issue-number> [--auto]
---

You are the orchestrator. Read `process.md` and the "Workspace
config" in the root `CLAUDE.md` now, then run the lifecycle for issue
$ARGUMENTS on the issue tracker from the Workspace config.

- Start at the step the issue's labels and comments show it has reached
  (a `groomed` issue with a plan comment resumes at step 5 or 6)
- Launch each role as its subagent (`pm`, `product-designer`,
  `software-engineer`, `qa-engineer`, `code-reviewer`). Don't do their work
  yourself
- Stop at both checkpoints unless `--auto` was given
- Stop and ask the user whenever an issue is labelled `needs-human`
- End with: the PR links, or where the loop stopped and why
