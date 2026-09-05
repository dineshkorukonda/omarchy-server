# Phase 0: Repo & Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute Phase 0 by renaming the application to `:ssh_client` (`SSHClient.*` namespace) and stripping Omarchy/QML-specific assets across Issues #53 and #54.

**Architecture:** Update Mix project metadata and module namespace from `OmarchyServer` to `SSHClient`. Rename directory structures (`lib/omarchy_server` -> `lib/ssh_client`, `test/omarchy_server` -> `test/ssh_client`), update test assertions and documentation, delete legacy QML UI files, open feature branch PRs, and merge to `main`.

**Tech Stack:** Elixir 1.17+, Git, GitHub CLI (`gh`).

**Spec:** [`SPEC.md`](file:///c:/Users/dines/Developer/ssh-client/SPEC.md) and [`docs/superpowers/specs/2026-09-05-ssh-client-revamp-design.md`](file:///c:/Users/dines/Developer/ssh-client/docs/superpowers/specs/2026-09-05-ssh-client-revamp-design.md).

## Global Constraints

- Mix application name: `:ssh_client`
- Module namespace: `SSHClient.*`
- Conventional Commits: `chore(rename): ...`, `chore(qml): ...`
- Feature branch pattern: `feat/<issue-number>-<slug>`
- PR target: `main`, assigned to `dineshkorukonda`, tagged with issue labels, brief description with `Closes #N`.

---

### Task 1: Issue #53 - Rename Project to ssh-client

**Branch:** `feat/53-rename-to-ssh-client`
**Files:**
- Modify: `mix.exs`
- Rename & Modify: `lib/omarchy_server.ex` -> `lib/ssh_client.ex`
- Rename & Modify: `lib/omarchy_server/` -> `lib/ssh_client/` (all 15 modules)
- Rename & Modify: `test/omarchy_server_test.exs` -> `test/ssh_client_test.exs`
- Rename & Modify: `test/omarchy_server/` -> `test/ssh_client/` (all test modules)
- Modify: `test/integration/ssh_daemon_integration_test.exs`
- Modify: `README.md`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create feature branch**
  `git checkout -b feat/53-rename-to-ssh-client`

- [ ] **Step 2: Update mix.exs**
  Change app name to `:ssh_client`, module to `SSHClient.MixProject`, mod to `{SSHClient.Application, []}`.

- [ ] **Step 3: Rename and update lib/ modules**
  Rename directory `lib/omarchy_server` to `lib/ssh_client`.
  Rename `lib/omarchy_server.ex` to `lib/ssh_client.ex`.
  Replace all `OmarchyServer` occurrences with `SSHClient` across `lib/`.

- [ ] **Step 4: Rename and update test/ modules**
  Rename directory `test/omarchy_server` to `test/ssh_client`.
  Rename `test/omarchy_server_test.exs` to `test/ssh_client_test.exs`.
  Replace all `OmarchyServer` occurrences with `SSHClient` across `test/`.

- [ ] **Step 5: Update README.md and start CHANGELOG.md**
  Update `README.md` title and description to `ssh-client`.
  Create `CHANGELOG.md` starting fresh with initial v0.2.0 note pointing back to `omarchy-server` history.

- [ ] **Step 6: Commit changes**
  `git commit -am "chore: rename project to ssh-client (#53)"`

- [ ] **Step 7: Push and open PR**
  `git push -u origin feat/53-rename-to-ssh-client`
  `gh pr create --title "chore: rename project to ssh-client" --body "Closes #53" --assignee dineshkorukonda --label "phase-0,chore"`
  Monitor CI and merge PR into `main`.

---

### Task 2: Issue #54 - Strip Omarchy/QML-specific files

**Branch:** `feat/54-strip-qml-files`
**Files:**
- Delete: `Panel.qml`
- Delete: `TerminalView.qml`
- Delete: `manifest.json`
- Delete: `Model.js`
- Delete: `test/ssh_client/plugin_test.exs`

- [ ] **Step 1: Switch to updated main and branch**
  `git checkout main && git pull origin main`
  `git checkout -b feat/54-strip-qml-files`

- [ ] **Step 2: Remove QML and plugin files**
  Delete `Panel.qml`, `TerminalView.qml`, `manifest.json`, `Model.js`, and `test/ssh_client/plugin_test.exs`.

- [ ] **Step 3: Commit deletion**
  `git commit -am "chore: strip Omarchy/QML specific files (#54)"`

- [ ] **Step 4: Push and open PR**
  `git push -u origin feat/54-strip-qml-files`
  `gh pr create --title "chore: strip Omarchy/QML specific files" --body "Closes #54" --assignee dineshkorukonda --label "phase-0,chore"`
  Monitor CI and merge PR into `main`.
