# aries migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/aries
- Remote: https://github.com/seanchatmangpt/aries (fork of plaans/aries)
- Branch: master@15bb08f9, upstream origin/master
- Last commit: 2026-09-16; commits: 2627; size: 46 MB
- Languages/build: Rust (Cargo.toml workspace, solver/, aries_fzn/), Python (pyproject.toml),
  justfile, paas/ (Ash/Elixir deployment work per recent commits)
- Nested repos: none

## Observed state
- dirty=0, untracked=4: all under docs/jira/v26.9.19/ (000-survey, 001-pr-3, 002/003 branch
  land-or-delete tickets)
- ahead=0 behind=0 on origin/master; stash=0
- Unpushed local branch: exp/fzn-set-in @70da8f1a (already merged into master by 15bb08f9)
- Build dirs: no target/ present
- Local-only files: .env at repo root (contents not inspected)
- Submodules: none

## What it is
Aries is a constraint-programming solver for automated planning and scheduling (CP + clause
learning, optional variables), with FlatZinc support and a Sean-added paas/ Ash layer. Fork of
plaans/aries with local feature work.

## Classification
WARM (census agrees: last commit 2 months ago, clean, pushed).

## Migration risk
- Uncommitted: 4 untracked jira docs (low value, easy to recommit).
- Unpushed: exp/fzn-set-in is merged into master, so nothing is lost if dropped.
- Local-only data: .env at root. Must travel by hand if it holds real config.
Rate: LOW

## Recommended action
COMMIT-PUSH
1. `cd /Users/sac/aries && git add docs/jira && git commit -m "docs(jira): v26.9.19 survey"`
2. `git push origin master`
3. `git branch -d exp/fzn-set-in` (merged; DECISION: keep if Sean wants the branch name)
4. Copy `.env` to the secrets vault manually; never commit it.
5. Then CLONE-FRESH on the new machine; no rsync needed.

## First commands on the new machine
`git clone https://github.com/seanchatmangpt/aries && cd aries && cargo check --workspace`
then `just --list` to confirm recipes resolve.

## See Also
- ../v26.9.19/
- /Users/sac/docs/jira/v26.11.16/README.md
