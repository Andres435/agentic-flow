---
name: test-verification
description: Scoped test policy for ticket work. Load when verifying a change; not always-on.
keywords: tests, scoped tests, regression, verification, test-first, conventions
---

# Test verification

Run the **smallest** test that proves the change. Prefer the nearest fixture or project over a
full-repo suite.

## Scoped test order

1. Run a single test or fixture filter when one directly matches the change.
2. Broaden to the nearest affected test project.
3. Broaden to a parent domain test set only when shared behavior or cross-component contracts changed.
4. Report unrelated restore, analyzer, or dependency failures instead of escalating to a full-suite run.
   Run the full suite only when the user asks.
5. Write the `.trx` or log to one fixed scratch path per repo, `tmp/<ticket>-<repo>-verify.trx`, and overwrite
   it each run; never `full2_`/`full3_` copies. `Set-VerifyReceipt.ps1` copies it to `plans/evidence/<ticket>/`.

## Bug fix and feature policy

1. Search for existing tests around the affected behavior.
2. Bugs: if a relevant test already fails, that is RED. If none exists, add the smallest regression
   test in the nearest fixture, confirm it fails for the expected reason, make the smallest
   production change, re-run it, then the nearest broader scope. Refactor only while green.
   When no test can reach the code (a page with no test project), the plan's first step says
   `no-test: <reason>` and the Drive is the proof.
3. Features: list observable behaviors from the acceptance criteria and ship them as slices — the
   smallest behavior that proves the path first, broaden only after it is green.
4. Quote pass/fail counts. Do not paste full logs unless the user asks.

## Conventions

- Name tests for observable behavior, not implementation. Arrange / Act / Assert, setup close to the behavior.
- Reuse existing fixtures, factories, and helpers before creating new ones.
- Mock at system boundaries only; never the unit under test, and never duplicate production logic in assertions.
- Async code gets async tests; no blocking waits.
- For legacy areas, prefer characterization tests around observable behavior, and get user approval
  before changing core shared logic.

The project's test command belongs in `environments/local-dev.md` (overlay). Do not invent a
runner the profile never named.
