---
description: Business case and 12-month marketing plan for one product (feasibility, financials, pricing, then marketing)
argument-hint: [product name or brief]
---

You are the orchestrator for a go-to-market plan. Read the "Business context"
and "Agent team notes" in the root `CLAUDE.md` now. Product: $ARGUMENTS

1. **Brief.** Build the product brief with the user, one question at a time,
   skipping what the Business context, the repo or the user already
   answered: what the product is and does, who it is for, the problem it
   solves, its stage (idea, beta, live, with any users or revenue), where it
   is sold, known competitors, the budget and the hours a week available for
   marketing, and the existing channels and accounts and who runs them.
   Save it to `docs/business/<yyyy-mm-dd>-<product-slug>/brief.md` and show
   the user a summary to confirm
2. **Business case.** Launch `ai-team:business-developer` with the brief path
   and that folder as the output folder. When it returns, show the user the
   verdict, positioning, price, base-scenario numbers and its open
   questions. Answer the questions with the user, update the brief, and
   relaunch it if the answers change the case. On a no-go verdict, ask
   whether to stop or continue
3. **Marketing plan.** Launch `ai-team:product-marketer` with the same brief
   path and output folder. Relay its open questions the same way
4. **Wrap up.** List the files written, then summarise: verdict, price,
   12-month base revenue and break-even, the top quick wins, and what to do
   this week. Offer to file the quick wins and the 3-month actions as issues
   on the tracker; file them only if the user agrees

Don't do the subagents' research or writing yourself. Commit the folder only
if the user asks.
