Orchestrator

The main session is the orchestrator. It launches the PM, the designer, the
engineer and QA as subagents. It does not groom, implement or test itself.
It owns the implementation plan, the git workspace setup, and closing issues.

Roles

- PO: Sets up project context based on chat with users or a given project brief, follows _docs/team/po.md
- PM: grooms a task before anyone implements it, follows _docs/team/pm.md
- Product Designer: Designs the neccesary screen, follows _docs/team/product-designer.md
- Engineer: implements one groomed task, follows _docs/team/software-engineer.md
- QA: checks the result against the acceptance criteria, follows _docs/team/qa-engineer.md

Lifecycle

1. PO sets up project and issues in the backlog
2. Pick the next open issue from the backlog
3. PM grooms it
4. Orchestrator writes the implementation plan and sets up the workspace
   (see "Implementation plan & workspace" below)
5. Product designer generates screens (only if the issue touches UI)
6. Engineer implements it, inside the workspace from step 4
7. QA verifies it, inside the same workspace
8. On FAIL, back to step 3 with the QA comment as input (reuse the workspace)
9. On PASS, open the PR(s) against the base branch, close the issue
10. Repeat until the backlog is empty

Workspace config

Each project that uses this team declares, in its own CLAUDE.md under a
"Workspace config" heading:

- Repos: the git repos work can touch (one repo, or several for a
  multi-repo/meta-repo project), with their paths
- Base branch: the integration branch features start from and PR into
  (e.g. `dev`), plus any repo that differs (e.g. `main` where there is no `dev`)
- Worktree root: where new worktrees go (default: `.worktrees/` at the
  project root, gitignored)
- Shared environments: deploy targets features must NOT deploy to from a
  feature branch (e.g. a shared dev/staging project)

If the project has no Workspace config, use: the current repo, base
`origin/dev` if it exists else `origin/main`, worktree root `.worktrees/`.

Implementation plan & workspace (step 4)

Before any code is written, the orchestrator posts an implementation plan as a
comment on the issue, covering:

- Repos touched: which repos from the Workspace config the change needs
- Branch name: `<type>/<issue-number>-<short-topic>`, the SAME name in every
  repo touched
- Base branch: from the Workspace config; PRs target that same base
- Conflict check: for each repo touched, the result of
  `git -C <repo> status --short`, `git -C <repo> branch --show-current` and
  `git -C <repo> worktree list`, and whether in-flight work overlaps this
  issue's files
- Workspace decision: in place or new worktree, with the absolute path for
  each repo

Workspace rule: if a repo has uncommitted changes, is on an unrelated branch,
or has in-flight work touching the same files/area, create a new worktree
instead of switching branches or stashing:

    git -C <repo> fetch origin
    git -C <repo> worktree add <worktree-root>/<repo>-<issue-number>-<short-topic> -b <branch> origin/<base>
    git -C <worktree> branch --unset-upstream   # so a bare `git push` can't hit the base branch

Work in place only when the repo is clean and on its base branch with nothing
in flight. In a new worktree, install dependencies and copy the gitignored
local env files (`.env*`) in from the main checkout.

The orchestrator passes the workspace paths to the designer, engineer and QA
in their prompts. Subagents never pick or create workspaces themselves.

Rules

- Tasks are GitHub issues, one at a time per orchestrator session. Parallel
  issues need separate orchestrator sessions, each in its own worktree(s), and
  must not touch the same files
- Read the acceptance criteria before starting and before closing
- Commit regularly, on the issue's branch, inside its workspace
- Do not skip grooming (step 3) or the implementation plan (step 4)
- Never deploy from a feature workspace to a shared environment listed in the
  Workspace config; test locally (emulators, local servers), on non-default
  ports if another checkout is already running them
- The engineer does not close the issue
- QA does not fix the code, only outputs PASS or FAIL
- The orchestrator closes the issue only after QA outputs PASS
- After the PR(s) merge, remove the worktree(s): `git -C <repo> worktree remove <path>`
