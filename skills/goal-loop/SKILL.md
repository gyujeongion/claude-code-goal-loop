---
name: goal-loop
description: Set a goal and let the agent work toward it in an autonomous loop — but carefully, verifying each step instead of charging ahead. Define the goal, success/failure criteria, and scope; snapshot for rollback; iterate in small steps, each gated by verification; when stuck, get a cross-model second opinion; when a change breaks things, do root-cause analysis before any patch; roll back honestly if it can't be solved. Use when you say "/goal-loop", "keep working until this is done", "loop on this until it passes", "autonomously get this feature working".
---

# /goal-loop — autonomous goal completion, verified step by step

## Core principle

**Don't stop until the goal is met — but move carefully, verifying as you go.**

No firefighting. Each iteration must pass verification before moving on. Any change that
risks destroying working state gets a snapshot first. The loop's job is to *converge on
the goal*, not to look busy.

This is an **instruction skill, not a runtime engine** — it's a protocol the agent
follows, not executable code that drives a state machine. Its value is the discipline it
imposes on an otherwise reckless "loop until it works." Within that loop it tells the
agent when to call three companion skills:
- a **sandbox verification gate** before accepting any change
  ([sandbox-gate](https://github.com/gyujeongion/claude-code-sandbox-gate))
- a **multi-model council** when stuck or unsure
  ([council](https://github.com/gyujeongion/claude-code-council))
- **root-cause redesign** when a change breaks existing behavior
  ([deusex](https://github.com/gyujeongion/claude-code-rootcause))

If you don't have those installed, substitute your own equivalents — the loop structure
is what matters.

---

## Phase 0 — Define the goal & snapshot the original

### 0-1. Specify the GOAL (agree with the user)

Before the loop starts, define these four clearly:

| Item | Meaning |
|------|---------|
| **GOAL** | What you're achieving — one clear sentence |
| **Success criteria** | "This must be true to be done" — an observable fact |
| **Failure criteria** | The state that means: stop the loop immediately and report |
| **Scope** | The files/systems you may touch — never modify outside this |
| **Budget** | Hard stop conditions: max iterations, and (if you can track them) a token/cost ceiling. The loop ends when *any* limit is hit, not just on success. |

If it's ambiguous, ask. Don't start on a guess.

### 0-1b. Break the goal into a task list

A single fuzzy goal converges slowly. Split it into an ordered, checkable task list
(a `tasks.md` / `progress.json` you keep updating) — each task small enough to finish
and verify in one iteration. Each iteration then picks the **highest-priority unfinished
task**, which keeps the loop focused and gives you a visible "X of N done" instead of a
vague "still working." This is the difference between a loop that wanders and one that
converges.

### 0-2. Snapshot the original (rollback point)

**Isolate the loop so rollback can never touch the user's other work.** This is the
single most important safety rule here.

**Git project — work in a throwaway worktree/branch, never on the user's main checkout:**
```bash
git worktree add ../goal-loop-<slug> -b goal-loop/<slug>   # main checkout stays untouched
cd ../goal-loop-<slug>
SNAPSHOT=$(git rev-parse HEAD)
```
- **Never `git add -A && git commit` on the user's main checkout** — that sweeps their
  unrelated, in-progress changes into your snapshot.
- If a worktree truly isn't possible, commit **only in-scope files** (`git add <scope>`)
  and record the SHA — never `-A`.

**Non-git files/scripts:**
```bash
cp -r <target> /tmp/goal-loop-snapshot-<timestamp>/
```

Record the snapshot location in-session. Reference it for recovery.

---

## Phase 1 — Plan the iteration

At the start of each iteration:

1. **Current state** — read the task list / `progress.json`; where the last iteration left off.
2. **Next task** — pick the single **highest-priority unfinished task** (not just "the next thing").
3. **Carry the last failure forward (feedback injection)** — if the previous iteration
   failed verification, feed its concrete result (the failing test output, the diff, the
   error) into this iteration's plan as explicit input. A loop that doesn't carry forward
   *why* the last attempt failed just repeats it. This is the single biggest lever on
   convergence speed.
4. **Impact estimate** — the files/functions/systems this step touches.
5. **Rollback point** — where you return to if this step fails.

> Don't make a big change at once. Split small, verify, advance.

> **Long loops — summarize, don't accumulate.** If the loop runs many iterations,
> don't drag the full history along. Keep a short running summary (tasks done, key
> decisions, current blockers) and work from that. Context bloat slows the loop and
> degrades judgment.

---

## Phase 2 — Implement & verify (gate every iteration)

### 2-1. Implement
- Touch only files in scope.
- Smallest possible change.
- One line logging the current state before changing it.

### 2-2. Verify (required every iteration)

After implementing, a verification gate must pass before the next step:

```
verify (sandbox-gate or your equivalent) → check the report
  ✅ all pass    → Phase 3 (progress check)
  ⚠️ warnings    → fix the flagged items, re-verify
  ❌ fail        → Phase 4 (stuck)
```

**Skipping verification and advancing is forbidden.** Unverified changes piling up means
you won't know where it broke.

---

## Phase 3 — Goal check

After each iteration, check **both** the goal and the stop conditions:

```
Success criteria met?            → YES: end the loop, final report (Phase 6)
Any budget limit hit?            → YES: stop and report what's left (Phase 6, partial)
   (max iterations / token / cost ceiling from Phase 0)
No progress for K iterations?    → YES: stop — don't grind. Go to Phase 4 (council) or
   (no task closed, same failure) report honestly. A loop that isn't converging won't
                                    start converging by repeating itself.
otherwise                        → back to Phase 1 for the next task
```

**Intelligent exit beats a fixed counter.** "Done" isn't only "success criteria true" —
it's also "budget spent" or "stalled K rounds in a row." Detect the stall (same error
twice, no task closed, verification flat) and break out to council or an honest report,
rather than burning the whole iteration budget making no progress.

### Pick the loop engine (development vs. operations — required)

Before looping, decide whether this is a **development/convergence** phase or an
**operations/standing** phase. They need different engines; the wrong one is inefficient
or unstable.

| | Development/convergence | Operations/standing |
|---|---|---|
| Goal | "make the code work" — still incomplete, fix toward convergence | "keep collecting / run periodically" — pipeline already built |
| Agent role | edit code each iteration + verification gate | re-run a finished process on a schedule |
| Right engine | an **in-session auto-loop** (e.g. a ralph-loop-style runner) | **launchd / cron running the *finished pipeline*** (session-independent, 24/7) |
| Verification | the gate every iteration | **bake the gate into the pipeline** (idempotent upsert, incremental, retry, healthcheck) |

**Development phase:** auto-loop in-session — the agent fixes toward the goal while the
session is alive.

**Operations phase:** don't use a session-bound loop — it's wrong for 24/7 work (dies
when the session ends, and burns tokens while an external process does the real job).
Schedule the **finished pipeline** (a script, a service — *not* the interactive agent;
never run claude-code itself unattended on a cron) and **bake the verification spirit
into that pipeline**: idempotency (dedupe, `ON CONFLICT`), incremental gates (only new
items), retry + healthcheck + auto recovery, and a stuck-handler. The agent's job ended
when it *built and verified* that pipeline; cron just runs it.

> Using cron isn't the violation. The real check is: **for an operations phase, did you
> bake the gate into the pipeline?** A cron without that is just firefighting.

---

## Phase 4 — When stuck: cross-model council

Call the council immediately when:
- the same error repeats 2+ times,
- you can't decide which direction to go,
- you suspect something is structurally wrong,
- verification passed but the logic feels unsafe.

Pass the council a summary of the situation, the stuck point, and what you've tried.
Then:
1. Shared agreement → follow it.
2. Disagreement → you (the agent) decide, with stated reasoning.
3. Both wrong → report to the user with your reasoning.

---

## Phase 5 — Function-breaking errors: root-cause first

Trigger root-cause redesign when:
- something that used to work is now broken,
- errors cascade (one fix breaks another place),
- the error message doesn't point at the real cause,
- the "just make it work for now" urge appears ← always root-cause this.

Order:
1. Root-cause diagnosis (complete the diagnosis phase — don't patch the symptom).
2. Take the diagnosis to the council for a structural-redesign cross-check.
3. Confirm the redesign → verify it in the sandbox first.
4. Apply to main only after it passes.

**Firefighting patches are never allowed.**

---

## Phase 5b — Unrecoverable: roll back to the original

Propose rollback if any of these hold:
- root-cause + council still yield no path forward,
- a structural change beyond the agreed scope is required (goal needs redefining),
- original functionality is broken and the recovery path is unclear.

### Rollback

**Git:** discard the loop's isolated work — never `git reset --hard` a shared working
tree (it destroys the user's unrelated changes too):
```bash
cd .. && git worktree remove goal-loop-<slug> --force   # throw away the whole attempt
# worked in place instead? restore ONLY in-scope files:  git restore -- <scope paths>
```
**Non-git:** `cp -r /tmp/goal-loop-snapshot-<timestamp>/ <target>/`

Then report to the user: what you tried, why you rolled back, what's needed to solve it
(more info, a different approach, a redefined scope).

**If it can't be solved, say so honestly. Don't keep going in a broken state.**

---

## Phase 6 — Final report

```
# goal-loop report

## GOAL
<the goal you set>

## Achievement
- Success criteria:
- How verified:
- Result:

## Run summary
- Total iterations:
- Council calls + key conclusions:
- Root-cause invoked? what it resolved:
- Mid-run rollback?

## Final state
- Files changed:
- Remaining issues (if any):
- Recommended next steps:
```

---

## Hard rules

| Forbidden | Why |
|-----------|-----|
| Advancing without the verification gate | unverified changes pile up; you lose track of where it broke |
| Retrying the same failed approach 3+ times | call the council first |
| Continuing in a function-broken state | root-cause the cause first |
| Large edits with no snapshot | don't create an unrecoverable state |
| `git add -A` snapshot or `git reset --hard` on the user's shared worktree | sweeps in / destroys their unrelated work — isolate in a worktree/branch instead |
| Running with no budget / stop condition | a loop with no ceiling can burn unbounded tokens — set max iterations + a stall limit up front |
| Looping while stalled K rounds | no progress won't fix itself by repeating — break to council or report |
| "Just make it work for now" | no firefighting; it has to be structurally right to advance |
| Pressing on while unable to solve it | report honestly and let the user decide |

---

## Companion skills

- a loop runner (e.g. ralph-loop-style) — the auto-iteration engine for dev phases
- [sandbox-gate](https://github.com/gyujeongion/claude-code-sandbox-gate) — the per-iteration verification gate
- [council](https://github.com/gyujeongion/claude-code-council) — multi-model cross-check when stuck
- [deusex](https://github.com/gyujeongion/claude-code-rootcause) — root-cause redesign when a change breaks things
