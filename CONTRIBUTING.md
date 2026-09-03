# Contributing Guidelines

Thank you for contributing to omarchy-server. Please follow these guidelines to ensure consistency across the codebase.

## Commits

- Conventional Commits format: `type(scope): summary`
  - Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`
  - Example: `feat(daemon): add per-server GenServer supervision`
- Imperative mood, lowercase summary, no period at end.
- No `Co-authored-by` trailers, ever — not for pairing, not for AI tools.
- No emojis in commit messages.
- Body explains why, not what, when the diff isn't self-explanatory.

## Issues

- Every feature or fix starts as an issue before code is written.
- Issue title follows the same type prefix as commits (`feat:`, `fix:`, etc.).
- Trivial fixes (typo, broken link) can skip the issue and go straight to PR.

## Pull Requests

- One PR per issue, linked via "Closes #N" in the PR description.
- Assign yourself to the PR before starting work, not after opening it.
- Keep PRs scoped to one issue — no drive-by unrelated changes.
- PR description: what changed, why, how it was tested.
- Must pass CI before merge.
- No emojis in PR titles or descriptions.
- Squash merge, so the final commit message follows the Conventional Commits rule above regardless of intermediate commit history.

## Code Style

- Small, single-responsibility functions/modules.
- No dead code, no commented-out code left in.
- Explicit error handling, no silent failures/swallowed errors.
- Descriptive names over comments explaining what code does.
- Comments explain why, not what.

## Before Implementing

- Check official documentation for the relevant tool/library before writing code against it (Elixir/OTP docs, Quickshell/Omarchy plugin docs) — don't guess APIs or manifest schemas from memory.
- If Superpowers (`obra/superpowers-marketplace`) is installed, use its brainstorming/planning skill before starting a non-trivial feature, and its systematic-debugging skill when investigating a bug, rather than jumping straight to a fix.

## No Emojis

- Anywhere: commits, PRs, issues, code comments, README, CHANGELOG.
