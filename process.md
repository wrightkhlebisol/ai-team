Orchestrator

The main session is the orchestrator. It launches the PM, the engineer
and QA as subagents. It does not groom, implement or test itself.

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
4. Product designer generates screens
4. Engineer implements it
5. QA verifies it
6. On FAIL, back to step 3 with the QA comment as input
7. On PASS, close the issue
8. Repeat until the backlog is empty

Rules

- Tasks are GitHub issues, one at a time
- Read the acceptance criteria before starting and before closing
- Commit regularly
- Do not skip step 2
- The engineer does not close the issue
- QA does not fix the code, only outputs PASS or FAIL
- The orchestrator closes the issue only after QA outputs PASS
