---
name: team-process
description: The ai-team agent loop (groom → plan → design → build → QA → review → PR) with this session as orchestrator. Use whenever a request will change code beyond a trivial fix (typo, one-line config, a change the user dictates exactly), even when asked in plain words, unless the user says to skip the process. Also loaded by /ai-team:work-issue, /ai-team:work-backlog and /ai-team:plan-project.
---

# Agent team process

## Orchestrator

The main session is the orchestrator. It runs the loop below and launches the
PM, designer, engineer, QA and reviewer as subagents (the `ai-team` plugin's
agents, launched as `ai-team:<role>`). It owns the implementation plan, the git workspaces,
labels, PRs and escalation. It does not groom, design, implement or test
itself.

Entry points:

- `/ai-team:work-issue <n> [--auto]`: run one issue through the loop
- `/ai-team:work-backlog [--auto]`: run open issues in waves, pipelined
  (see Pipelining)
- `/ai-team:plan-project`: PO session to shape scope and file issues
- `/ai-team:plan-go-to-market`: business case and 12-month marketing plan
  for a product (business-developer, then product-marketer). Not part of
  the code loop: it writes documents under `docs/business/`, not code

Any request that will change code beyond a trivial fix (typo, one-line
config, a change the user dictates exactly) goes through this loop, even when
the user asks in plain words ("add X to the settings page"). File an issue for it
first if none exists. Skip the loop only when the user says so ("skip the
process", "just do it").

## Roles

| Role | Runs as | Default model | Changes code? |
| --- | --- | --- | --- |
| PO | the main session (it talks to the user), following `po.md` in this skill's folder | the user's choice | no |
| PM | `ai-team:pm` subagent | opus | no |
| Product designer | `ai-team:product-designer` subagent | opus | no (specs and mockups only) |
| Engineer | `ai-team:software-engineer` subagent | opus | yes |
| QA | `ai-team:qa-engineer` subagent | opus | no |
| Reviewer | `ai-team:code-reviewer` subagent | fable | no |
| Business developer | `ai-team:business-developer` subagent (go-to-market only) | opus | no (business docs only) |
| Product marketer | `ai-team:product-marketer` subagent (go-to-market only) | opus | no (marketing docs only) |

Each role's rules live in its agent definition. Project-specific rules for a
role go in the project's "Agent team notes" (see Workspace config).

### Models

Each agent's frontmatter sets its default model, so subagents never inherit
the main session's model by accident. A subagent with no model set runs on
whatever the main session uses, which is often the most expensive tier.

- The reviewer defaults to `fable`: it is the last check before a PR and
  catches what the cheaper roles miss
- Pass `model` on the launch to change one run. Raise the engineer to `fable`
  for issues that touch money, authentication, authorisation or data
  migrations, and for a fix round after a blocking review. Use `sonnet` for a
  pure lookup
- A resumed subagent keeps the model it started with. To run a follow-up on
  a cheaper model, launch a fresh agent with the full brief instead
- A project can set its own defaults per role in its "Agent team notes"
  (e.g. `model: sonnet` under `### code-reviewer`); notes win over these

Subagents can't ask the user anything. Anything that needs a human decision
comes back to the orchestrator, which asks.

Every subagent prompt includes: the issue number, the issue tracker repo,
the workspace path(s), the branch, and (on a retry) the comment it must
address. QA prompts also state the QA mode (see QA mode).

## Lifecycle

1. **Pick.** Take the issue (`/ai-team:work-issue <n>`) or the next open issue that
   is not labelled `needs-human`, `in-progress` or `ready-for-review`. Read
   it in full, including comments.
2. **Groom.** Launch `pm`. Done when the issue body follows
   the task template (Goal, Acceptance criteria, Out of scope, Constraints)
   and it is labelled `groomed`.
3. **Plan.** Orchestrator posts the implementation plan comment and sets up
   the workspaces (see below). Label `in-progress`.
4. **Checkpoint 1: plan approval.** Show the user the acceptance criteria
   and the plan. Continue on approval. Skipped in `--auto` mode.
5. **Design** (only if the issue changes UI). Launch `product-designer`.
   Done when the design spec comment is on the issue.
6. **Build.** Launch `software-engineer` in the workspace(s).
7. **Verify.** Launch `qa-engineer` in the same workspace(s): `e2e` mode
   when the issue has UI-only criteria, else `automated` (see QA mode).
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

## QA mode

QA runs in one of two modes, and the orchestrator names the mode in every
QA prompt:

- `automated`: tests, linter, type check, and API calls against local
  servers or emulators. No UI driving. UI-only criteria are marked
  `PENDING E2E`, not PASS
- `e2e`: everything in `automated`, plus the UI walk: driving the real app
  on a simulator, emulator or browser and checking what each screen shows

Rules:

- **Walk headless by default.** QA drives the app from the command line,
  on its own simulator, emulator or browser instance, without taking over
  the user's screen, mouse or keyboard (see "Headless walk" below). Use
  screen control (computer use, GUI scripting) only for a criterion that
  depends on real touch or pointer input, and only when no other session
  holds the screen. Never wait on a screen-control lock when the headless
  walk can do the step

- **The UI walk is QA's job, not the user's.** An issue with criteria that
  can only be checked in the UI gets `e2e` QA. Never ask the user to check
  screens by hand as a step of the loop, and never hold a PR for a hand
  check
- An issue with no UI-only criteria gets `automated` QA
- The walk is the costliest step in the loop, so keep it small:
  - Walk only the screens and states the acceptance criteria name
  - One walk per issue. Retry rounds after a FAIL re-check the failed
    criteria only, in `automated` mode where they can be checked that way
  - Issues that share an app and a branch (or are already merged to the
    same base) are walked together by one QA run, with a verdict per issue
  - Walks that share a simulator, emulator or browser profile run one at a
    time. Builds and `automated` QA for other issues keep moving meanwhile
- A FAIL in either mode counts toward the 2-round cap as usual
- If the walk can't run (no simulator or browser available, or the app
  won't build for a reason outside the issue), QA returns `PASS (PENDING
  E2E)`. Fix the environment and re-run the walk. Label `needs-e2e` and
  tell the user only when it can't be fixed from the session
- The user can turn walks off ("no e2e for now", or a line in the project's
  "Agent team notes"). Then QA runs `automated`, issues with UI-only
  criteria wait as `needs-e2e`, and the walks run once the user turns them
  back on

### Headless walk

Screen control gives one session the cursor: a second session's walk waits
for it, and every action costs a screenshot. A headless walk needs neither,
so walks in different sessions can run at the same time.

- **Own instance.** QA uses a simulator, emulator or browser instance of
  its own, booted from the command line with no window, and a dev server
  or bundler from the issue's workspace on a non-default port. It never
  touches an instance or server another session started, and removes its
  own when done
- **Read the screen as data.** QA reads what the running app renders
  (web: the DOM or accessibility tree through a headless browser such as
  Playwright; mobile: the rendered component tree through the app's
  debugger or inspector, or the platform's UI-hierarchy dump) and checks
  the text, labels and current route against the criteria
- **Act through the same channel.** Press, type and navigate from code
  (browser automation calls; on mobile, the element's own press and text
  handlers, deep links and the platform's device commands)
- **Screenshots as evidence, not as eyes.** One command-line screenshot per
  step, and QA looks at each: a tree that reads right on a blank or
  crashed screen is a FAIL
- **Keep the driver.** The script that connects and drives the app lives in
  the project (the "Agent team notes" say where). QA reuses it and never
  rewrites it per issue; an engineer fixes it when the app outgrows it
- **Say what it can't see.** A headless walk does not catch real-touch
  problems (a button under another element, gestures, the on-screen
  keyboard). When a criterion depends on those, the verdict says so and
  that step is done with screen control, or stays `PENDING E2E`
- The verdict names the method ("headless walk")

A project records its own recipe (how to boot an instance, load the
branch, connect the driver, sign in a test account) in its "Agent team
notes" under `qa-engineer`. The orchestrator passes the instance, the port
and the driver path in the QA prompt.

### Human check (only on request)

The user may still ask to check a branch themselves. Then:

1. Serve the branch from its own workspace on a non-default port (a second
   dev server or bundler) and open it on the user's simulator, emulator or
   browser. Never switch, detach or stash the user's main checkout to do it
2. Give numbered steps, one action each, with the expected result after
   each, and the test account and data to use
3. Record the result on the issue. A failed step goes back to step 6 with
   the user's report as the QA comment
4. Stop the extra server when the check is done

A human check is extra. It never replaces the `e2e` walk, and the loop
never waits for one the user didn't ask for.

## Labels

Labels show the state of an issue, so a fresh session can resume from the
issue alone. Create missing ones with
`gh label create <name> --force -R <tracker>`.

`groomed` → `in-progress` → (`qa-fail`) → (`needs-e2e`) →
`ready-for-review`, plus `needs-human` whenever the loop is blocked on a person. Remove the previous
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
- Design system: where it lives (README first), if the project has UI
- Test environment: how features are tested locally (emulators, local
  servers, seeded data), and on which ports
- Resource budget (optional): the share of free CPU/RAM agents may use
  (default 50%) or an absolute target for the whole machine,
  a costs file for `capacity.sh` with measured profiles for this project,
  the test-runner worker cap, the number of `heavy.sh` slots, and the most
  simulators/emulators at once

For the go-to-market roles, the same `CLAUDE.md` can hold a "Business
context" section: company stage, budget, team and hours available,
existing channels and accounts (and who runs them), markets, currency, brand
voice. Missing → a bootstrapped company with little to no budget, USD.

Missing config → defaults: the current repo, base `origin/dev` if it exists
else `origin/main`, worktree root `.worktrees/`, tracker = the current repo.

Optionally, an "Agent team notes" section in the same `CLAUDE.md` adds
project rules per role, as a `### <role>` heading each (`pm`,
`product-designer`, `software-engineer`, `qa-engineer`, `code-reviewer`,
`business-developer`, `product-marketer`, `orchestrator`): the checks a reviewer must make, where the screens live,
domain conventions. Every agent reads its entry first; notes win over the
generic rules where they disagree.

## Implementation plan & workspace (step 3)

Read the "Workspace config" (above) (repos, base branches,
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
on its base branch with nothing in flight. In a new worktree,
install dependencies and copy the gitignored local env files (`.env*`) in from the
main checkout.

Subagents never pick, create or switch workspaces themselves.

## Pipelining

The orchestrator keeps work moving instead of waiting on one subagent at a
time. Subagents run in the background; launch independent ones together,
as many as the resource budget admits (see Resource budget).

- **Groom ahead.** Grooming changes no code. While an issue is being built,
  groom the upcoming ones in parallel (one PM subagent per few issues).
  Groomed criteria written before a dependency lands can go stale: QA sends
  a wrong criterion back to step 2 as usual
- **Design ahead.** Design specs are issue comments, not code. Launch the
  designer for any groomed UI issue whose design-system dependency is in
  place (or is the issue being designed)
- **Build in parallel.** Two issues can be built at the same time when
  neither depends on the other and they edit different files. Each gets
  its own worktree and branch. Checkpoint 1 still applies per issue; a user
  asking to run an issue in parallel approves starting it, but show them
  its criteria and plan
- **Stack on in-flight dependencies.** If an issue needs another's
  unmerged work, branch from that issue's branch instead of waiting:

      git -C <repo> worktree add <worktree-root>/<repo>-<n>-<topic> -b <branch> <parent-branch>

  Record `Base: <parent-branch> (stacked on #<parent>)` in the plan. Give
  reviewer and QA that base. Open the PR against the parent branch, say
  "Stacked on #<parent>'s PR" in the body, and retarget it to the base
  branch once the parent merges (rebase if needed)
- **Share setup files carefully.** When a parallel issue needs something
  the in-flight issue owns (dependencies, test config), don't edit those
  files in both branches. Use a temporary, uncommitted workaround (e.g.
  `npm i --no-save`) and state in the plan how QA runs the checks until
  the owner merges
- **Checkpoints don't block others.** While one issue waits for the user at
  a checkpoint, keep the other in-flight issues moving

## Resource budget

Parallel agents share one machine. What costs resources is not the agent
(it runs inside the Claude Code process) but what it runs: test suites,
builds, dev servers, simulators and emulators. Too many at once can freeze or
crash the machine and lose every agent's work. By default the agents get
**50% of the CPU and RAM that is free** when they launch, so whatever the
user already has open never counts against them and the rest stays free for
the user. A project can instead set an absolute target (the whole machine at
most N% busy).

Two scripts in this skill's `scripts/` folder do the work:

- `capacity.sh [--share PCT | --target PCT] [--costs FILE] ROLE[=N] ...`
  measures CPU load, RAM in use and booted simulators, works out the budget
  (`--share`, the default at 50: that share of what is free; `--target`:
  up to that share of the whole machine), and admits the requested roles in
  the order given, by their cost profile
  (expected peak RAM and cores of what that role runs). It prints what to
  launch now and what to queue. Profiles: `pm`, `product-designer`,
  `code-reviewer`, `software-engineer`, `engineer-native` (native/mobile
  builds), `qa-engineer`, `qa-sim` (QA driving a simulator or emulator),
  `simulator`. Projects override or add profiles in a costs file
- `heavy.sh [--slots N] [--name POOL] -- CMD ...` runs a heavy command only
  when a machine-wide slot is free (default 1 slot), so agents queue for the
  full test suite or a native build instead of running them all at once.
  Slots held by a dead process are reclaimed

Before every launch of one or more subagents (a wave, a retry, a refill):

1. Run `capacity.sh` with the roles you want to launch, most important first
   (blocking fixes before new work, builds before reviews). Use the share
   or target and the costs file from the Workspace config, if any
2. Launch only what it admits. Keep the rest in a queue, and as each agent
   finishes, run `capacity.sh` again and launch the next from the queue.
   Don't re-measure right after a launch: new agents haven't started their
   heavy commands yet, so the machine looks freer than it is. If it reports
   the machine already over target (`--target` mode), launch nothing that runs
   heavy commands; light roles (`pm`, `code-reviewer`) may still go if they fit
3. Free what you no longer need before measuring: shut down simulators and
   emulators no agent is using, stop dev servers of finished issues

Every subagent prompt that runs commands includes the limits it must keep:

- the absolute path to `heavy.sh`, and that full test suites, type checks of
  the whole repo, native builds and UI-test runs go through it
  (`--name build` for native builds)
- the cap on test-runner workers (e.g. Jest `--maxWorkers=2`, pytest
  `-n 2`), or the project's value, and on native build jobs
  (`xcodebuild -jobs 4`, Gradle `--max-workers=4`). The slot lock stops two
  builds running at once, but an uncapped build still uses every core
- the one simulator/emulator it may use (by id) and, if it boots one, to
  shut it down before handing back. Never more than the number of `qa-sim`
  agents admitted
- that one agent runs the repo-wide checks for a parallel QA pass and the
  others cite its results, run only their own test files, and rerun a
  timed-out test alone before calling it a failure

## Rules

- Keep within the resource budget (see Resource budget): measure before
  launching, queue what doesn't fit
- Don't wait idle. While a subagent works, launch the next independent
  step (see Pipelining). Several issues may be in flight in one session;
  each build runs in its own worktree, and no two in-flight builds edit
  the same files
- Read the acceptance criteria before starting and before opening the PR
- Commit regularly, on the issue's branch, inside its workspace, using
  conventional commits (`feat(web): …`, `fix(api): …`)
- Do not skip grooming (step 2) or the plan (step 3)
- Never deploy from a feature workspace to a shared environment listed in
  the Workspace config. Test locally (emulators, local servers), on
  non-default ports if another checkout already runs them
- QA and review run per issue, as soon as its build is done. Don't hold
  them until a whole backlog or wave is built, and don't wait for other
  issues or plan updates before verifying a finished build
- An issue reaches a PR, is approved, or is closed (by hand or by merge)
  only with QA PASS and no blocking review findings.
  `PASS (PENDING E2E)` is not a PASS: the issue waits until the `e2e`
  walk has run and passed (see QA mode)
- Never make a hand check by the user a step of the loop. The UI walk is
  QA's job
- Only the user merges PRs
