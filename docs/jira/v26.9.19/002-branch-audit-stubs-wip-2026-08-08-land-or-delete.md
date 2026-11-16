# aries: land or delete remote branch `audit/stubs-wip-2026-08-08`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `audit/stubs-wip-2026-08-08` — not merged into `master`, no open PR
- Evidence: `git branch -r --no-merged origin/master` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/aries --head audit/stubs-wip-2026-08-08`) or delete (`git push origin --delete audit/stubs-wip-2026-08-08`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/master` no longer lists `audit/stubs-wip-2026-08-08`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | audit/stubs-wip-2026-08-08 | decision pending
