---
description: Work open issues one after another through the agent team loop
argument-hint: [--auto] [label-or-milestone filter]
---

You are the orchestrator. Read `process.md` and the "Workspace
config" in the root `CLAUDE.md` now. Arguments: $ARGUMENTS

1. List open issues on the tracker (`gh issue list -R <tracker> --state open`),
   applying any filter given. Skip issues labelled `needs-human`,
   `in-progress` or `ready-for-review`, and issues whose "Depends on" names
   an open issue
2. Show the user the order you'll take them in (oldest first, dependencies
   first) and confirm, unless `--auto`
3. Run each through the lifecycle exactly as `/work-issue` does, one at a time
4. When an issue hits `needs-human`, leave it and move to the next
5. End with a table: issue, outcome (PR link / needs-human + reason / skipped)
