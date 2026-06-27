# claude-code-goal-loop

**"Keep going until it's done" — without the agent charging ahead and breaking things.**

A [Claude Code](https://claude.com/claude-code) skill that turns a goal into an
autonomous loop with guardrails: define the goal and its success/failure criteria,
snapshot for rollback, then iterate in small steps where **every step is gated by
verification**, a **cross-model council** breaks ties when stuck, and a **root-cause
pass** runs before any patch when something breaks.

---

## The problem with "just loop until it works"

Autonomous agent loops fail in two opposite ways:

- **They stop too early** — one happy-path success and they declare the goal met.
- **They run off a cliff** — they charge ahead, pile unverified changes on top of each
  other, break something three steps back, and have no way to return to a known-good
  state.

`/goal-loop` is the middle path: it doesn't stop until the success criteria are
*observably* true, but it advances one verified step at a time, snapshots before risky
changes, and knows when to stop and ask instead of digging deeper.

## How it works

```
Phase 0  Define GOAL + success/failure/scope, snapshot for rollback
Phase 1  Plan the smallest next step
Phase 2  Implement → VERIFY (gate) ──fail──▶ Phase 4
Phase 3  Goal met? ──no──▶ Phase 1   ──yes──▶ Phase 6 report
Phase 4  Stuck / repeated error ──▶ multi-model COUNCIL ──▶ Phase 1
Phase 5  A change broke something ──▶ ROOT-CAUSE redesign ──▶ re-verify
Phase 5b Unrecoverable ──▶ roll back to snapshot + honest report
Phase 6  Final report: iterations, council calls, what changed
```

Design choices that do most of the work:

- **A verification gate every iteration.** No advancing on an unverified change — that's
  how you lose track of where it broke.
- **A rollback snapshot before the loop starts.** "Keep trying autonomously" is only
  safe if there's always a known-good state to return to.
- **A task list, not a fuzzy goal.** The goal is split into ordered, checkable tasks;
  each iteration takes the highest-priority unfinished one. You get "X of N done", not
  "still working."
- **Feedback injection.** A failed iteration's actual output (failing test, diff, error)
  is fed into the next iteration's plan — so it fixes the cause instead of repeating it.
- **Budget + stall detection.** The loop stops on success, on a budget ceiling (max
  iterations / tokens / cost), *or* when it's made no progress for K rounds — instead of
  grinding forever. Intelligent exit beats a fixed counter.

### One non-obvious thing: dev loop vs. ops loop

A lot of autonomous loops waste tokens by running a session-bound loop for work that
should be a cron job. This skill makes you pick up front:

- **Development/convergence** ("make this work") → an in-session auto-loop that edits and
  re-verifies until it converges.
- **Operations/standing** ("keep collecting / run nightly") → **don't** hold a session
  open; schedule the **finished pipeline** with launchd/cron and **bake the verification
  into that pipeline** (idempotency, incremental gates, retry, healthcheck). To be clear:
  cron runs your built script/service, *not* claude-code itself — you never schedule an
  interactive agent unattended. A session loop here just burns tokens while an external
  process does the real work.

## What it is (and isn't)

`goal-loop` is a **pure instruction skill** — a protocol the agent follows, not
executable code that drives a state machine. There's no engine here that "runs" your
loop; the discipline (define-snapshot-verify-or-rollback) is the deliverable, the same
way a good code-review checklist is. It acts as a conductor, telling the agent when to
reach for companion skills. Install whichever you use, or substitute your own — the loop
structure is the point:

| Moment | Companion |
|---|---|
| Verify each change before accepting it | [sandbox-gate](https://github.com/gyujeongion/claude-code-sandbox-gate) |
| Stuck, repeated error, unsure direction | [council](https://github.com/gyujeongion/claude-code-council) |
| A change broke existing behavior | [deusex](https://github.com/gyujeongion/claude-code-rootcause) |
| The auto-iteration engine for dev phases | a ralph-loop-style runner |

## Install

```bash
git clone https://github.com/<you>/claude-code-goal-loop.git
cp -r claude-code-goal-loop/skills/goal-loop ~/.claude/skills/goal-loop
```

Pure instruction skill — no dependencies, no scripts, no API keys. The companion skills
are optional; without them the loop still runs, just substitute your own verification and
review steps.

## Usage

- `/goal-loop` — then state the goal
- `"keep working on this until the tests pass"` — triggers the loop
- `"autonomously get this feature working, verify as you go"` — same

It will refuse to call the goal done on a single happy-path pass, snapshot before risky
changes, and roll back with an honest report rather than dig a deeper hole.

## Prior art

The autonomous "loop until done" pattern is well-trodden — the
[ralph-loop family](https://github.com/snarktank/ralph)
([vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent),
[frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code), and
others) established it, and the task-list/feedback-injection/budget/stall ideas here come
straight from looking at how those tools work. The difference in emphasis: this is a
**pure protocol** (no engine to install), it foregrounds **safety** (isolated-worktree
snapshot, never `reset --hard` on a shared tree), and it makes the **dev-loop vs.
ops-cron** decision explicit so you don't burn tokens looping over work a cron should do.
If you want a runnable loop engine, use the ralph tools; this is the discipline layer.

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Anthropic.
