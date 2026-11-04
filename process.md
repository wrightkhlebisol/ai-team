# Agent team process

## Orchestrator

The main session is the orchestrator. It runs the loop below and launches the
PM, designer, engineer, QA and reviewer as subagents (defined in
`.claude/agents/`). It owns the implementation plan, the git workspaces,
labels, PRs and escalation. It does not groom, design, implement or test
itself.

Entry points:

- `/work-issue <n>`: run one issue through the loop
- `/work-backlog [--auto]`: run open issues one after another
- `/plan-project`: PO session to shape scope and file issues

Any request that will change code beyond a trivial fix (typo, one-line
config, a change the user dictates exactly) goes through this loop, even when
the user asks in plain words ("add X to the settings page"). File an issue for it
first if none exists. Skip the loop only when the user says so ("skip the
process", "just do it").

## Roles

| Role | Runs as | Follows | Changes code? |
| --- | --- | --- | --- |
| PO | the main session (it talks to the user) | `_docs/team/po.md` | no |
| PM | `pm` subagent | `_docs/team/pm.md` | no |
| Product designer | `product-designer` subagent | `_docs/team/product-designer.md` | no (specs and mockups only) |
| Engineer | `software-engineer` subagent | `_docs/team/software-engineer.md` | yes |
| QA | `qa-engineer` subagent | `_docs/team/qa-engineer.md` | no |
| Reviewer | `code-reviewer` subagent | `_docs/team/code-reviewer.md` | no |

Subagents can't ask the user anything. Anything that needs a human decision
comes back to the orchestrator, which asks.

Every subagent prompt includes: the issue number, the issue tracker repo,
the workspace path(s), the branch, and (on a retry) the comment it must
address.

## Lifecycle

1. **Pick.** Take the issue (`/work-issue <n>`) or the next open issue that
   is not labelled `needs-human`, `in-progress` or `ready-for-review`. Read
   it in full, including comments.
2. **Groom.** Launch `pm`. Done when the issue body follows
   `_docs/task-template.md` and it is labelled `groomed`.
3. **Plan.** Orchestrator posts the implementation plan comment and sets up
   the workspaces (see below). Label `in-progress`.
4. **Checkpoint 1: plan approval.** Show the user the acceptance criteria
   and the plan. Continue on approval. Skipped in `--auto` mode.
5. **Design** (only if the issue changes UI). Launch `product-designer`.
   Done when the design spec comment is on the issue.
6. **Build.** Launch `software-engineer` in the workspace(s).
7. **Verify.** Launch `qa-engineer` in the same workspace(s).
   - FAIL because the code is wrong → back to step 6 with the QA comment.
   - FAIL because a criterion is wrong, contradictory or untestable → back
     to step 2 with the QA comment.
   - Label `qa-fail` while a FAIL is open. After **2 failed rounds** (QA or
     review), stop, label `needs-human`, and summarise the blocker for the
     user.
8. **Review.** Launch `code-reviewer` on the branch diff. Blocking findings
   → back to step 6 (counts toward the same 2-round cap). Non-blocking
   findings go in the PR description.
9. **Checkpoint 2: before PR.** Show the user the QA verdict, the review
   summary and the diff stat. Skipped in `--auto` mode.
10. **PR.** Push the branch and open one PR per repo touched, against its
    base branch. The PR body links the issue (`Closes <tracker>#<n>` when
    the repo is not the tracker, else `Closes #<n>`) and the issue's other
    PRs. Label `ready-for-review`. The issue closes when its PR merges.
    The user merges; agents never merge.
11. **Clean up** after merge: `git -C <repo> worktree remove <path>`.

`--auto` skips the two checkpoints, never the 2-round cap or `needs-human`.

## Labels

Labels show the state of an issue, so a fresh session can resume from the
issue alone. Create missing ones with
`gh label create <name> --force -R <tracker>`.

`groomed` → `in-progress` → (`qa-fail`) → `ready-for-review`, plus
`needs-human` whenever the loop is blocked on a person. Remove the previous
state label when adding the next.

## Workspace config

Each project using this team declares, in its root `CLAUDE.md` under a
"Workspace config" heading:

- Repos: the git repos work can touch, with paths (one repo, or several for
  a multi-repo/meta-repo project)
- Base branch: the integration branch features start from and PR into
  (e.g. `dev`), plus any repo that differs
- Worktree root: where new worktrees go (default `.worktrees/` at the
  project root, gitignored)
- Shared environments: deploy targets never to deploy to from a feature
  branch
- Issue tracker: the GitHub repo that holds the backlog
- Design system: where it lives (see `_docs/team/product-designer.md`)

Missing config → defaults: the current repo, base `origin/dev` if it exists
else `origin/main`, worktree root `.worktrees/`, tracker = the current repo.

## Implementation plan & workspace (step 3)

Read the "Workspace config" (see below) (repos, base branches,
worktree root, shared environments, issue tracker). Then post the plan as an
issue comment:

```
## Implementation plan
Repos: api, web
Branch: feat/<n>-<short-topic> (same name in every repo)
Base: origin/<base> (PRs target <base>)
Conflict check:
- api: clean, on dev, nothing in flight → in place
- web: 3 uncommitted files on feat/other-thing, overlaps src/checkout/ → new worktree
Workspaces:
- /abs/path/api
- /abs/path/.worktrees/web-<n>-<short-topic>
Order: API endpoint first, then UI
Test plan: local servers on alternate ports
```

For each repo touched, the conflict check records
`git -C <repo> status --short`, `git -C <repo> branch --show-current` and
`git -C <repo> worktree list`.

Workspace rule: if a repo has uncommitted changes, is on an unrelated
branch, or has in-flight work touching the same files/area, create a new
worktree. Never switch branches or stash in someone's checkout:

    git -C <repo> fetch origin
    git -C <repo> worktree add <worktree-root>/<repo>-<n>-<short-topic> -b <branch> origin/<base>
    git -C <worktree-root>/<repo>-<n>-<short-topic> branch --unset-upstream

`--unset-upstream` stops a bare `git push` from pushing to the base branch; push with
`git push -u origin <branch>`. Work in place only when the repo is clean and
on its base branch with nothing in flight. In a new worktree, run
install dependencies and copy the gitignored local env files (`.env*`) in from the
main checkout.

Subagents never pick, create or switch workspaces themselves.

## Rules

- One issue at a time per orchestrator session. Parallel issues need
  separate sessions, each in its own worktrees, with no shared files
- Read the acceptance criteria before starting and before opening the PR
- Commit regularly, on the issue's branch, inside its workspace, using
  conventional commits (`feat(web): …`, `fix(api): …`)
- Do not skip grooming (step 2) or the plan (step 3)
- Never deploy from a feature workspace to a shared environment listed in
  the Workspace config. Test locally (emulators, local servers), on
  non-default ports if another checkout already runs them
- An issue reaches a PR only with QA PASS and no blocking review findings
- Only the user merges PRs
