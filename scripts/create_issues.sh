#!/usr/bin/env bash
# Creates every issue from SPEC.md section 5 via `gh`.
# Requires: `gh auth login` already done, run from inside the target repo
# (or pass -R owner/repo as an extra arg appended to every call below).
#
# Usage:
#   ./scripts/create_issues.sh
#   ./scripts/create_issues.sh -R dineshkorukonda/ssh-client

set -euo pipefail
REPO_FLAG=("$@")

create() {
  local title="$1" body="$2" labels="$3" milestone="$4"
  gh issue create \
    --title "$title" \
    --body "$body" \
    --label "$labels" \
    --milestone "$milestone" \
    "${REPO_FLAG[@]}"
}

# Ensure milestones exist
for m in "Phase 0 - Repo & rename" "Phase 1 - SSH transport core" \
         "Phase 2 - Desktop shell" "Phase 3 - Interactive terminal" \
         "Phase 4 - Host management" "Phase 5 - Credential storage" \
         "Phase 6 - Monitoring & management parity" "Phase 7 - TUI parity check" \
         "Phase 8 - Packaging & CI"; do
  gh api "repos/{owner}/{repo}/milestones" -f title="$m" >/dev/null 2>&1 || true
done

# --- Phase 0 ---
create "Rename project to ssh-client" \
"mix.exs app name (:ssh_client), module namespace SSHClient.*, README.md, repo description, fresh CHANGELOG with a note pointing back to omarchy-server history.

Acceptance criteria:
- [ ] mix.exs app/module renamed (:ssh_client, SSHClient)
- [ ] All lib/ modules under SSHClient.* namespace
- [ ] README title/description updated
- [ ] CHANGELOG.md started" \
"phase-0,chore" "Phase 0 - Repo & rename"

create "Strip Omarchy/QML-specific files" \
"Remove Panel.qml, TerminalView.qml, Omarchy plugin manifest. Keep lib/, test/, monitoring logic untouched for now — this issue is deletion-only, no new logic.

Acceptance criteria:
- [ ] Panel.qml, TerminalView.qml removed
- [ ] Omarchy plugin manifest removed
- [ ] Existing tests still pass" \
"phase-0,chore" "Phase 0 - Repo & rename"

# --- Phase 1 ---
create "Replace shelled ssh calls with :ssh_connection exec channel" \
"Port the monitoring commands (CPU/RAM/disk/uptime polling) off shelling to the system ssh binary and onto Erlang's :ssh_connection exec channel directly.

Acceptance criteria:
- [ ] No System.cmd/shell calls to 'ssh' remain in monitoring path
- [ ] Same metrics collected, same GenServer-per-host model
- [ ] Works against a Linux target from both a Linux and Windows dev machine" \
"phase-1,feature" "Phase 1 - SSH transport core"

create "Implement :ssh auth callback module" \
"Support key, password, and keyboard-interactive auth, selected per host from Host.auth_method. Keyboard-interactive matters specifically for cloud VMs (GCP etc.) that reject plain password auth.

Acceptance criteria:
- [ ] Key auth: tries id_ed25519, id_rsa, custom path, in order
- [ ] Password auth via :ssh password callback
- [ ] Keyboard-interactive via generic prompt-answer callback, not hardcoded to a single password field
- [ ] Per-host auth order override respected" \
"phase-1,feature" "Phase 1 - SSH transport core"

create "Host-key verification & fingerprint diff flow" \
"Reject-by-default on host key mismatch. Surface the event distinctly to the UI layer (old fingerprint vs new) rather than folding it into a generic connection error.

Acceptance criteria:
- [ ] First-connect: fingerprint shown, explicit accept required
- [ ] Changed key: diff shown (old vs new), explicit accept/reject, no silent auto-accept
- [ ] Known-hosts persisted correctly" \
"phase-1,feature" "Phase 1 - SSH transport core"

# --- Phase 2 ---
create "Bootstrap elixir-desktop" \
"New window, minimal LiveView 'hello' page rendering natively on both a Windows and a Linux dev machine.

Acceptance criteria:
- [ ] App launches as a native window on Windows (WebView2)
- [ ] App launches as a native window on Linux (WebKitGTK)
- [ ] Hot-reload/dev workflow documented in README" \
"phase-2,feature" "Phase 2 - Desktop shell"

create "Port host-list + status UI from QML to LiveView" \
"Same data as the old QML panel, new LiveView template. Parity milestone only — no new features here.

Acceptance criteria:
- [ ] Host list renders with live status
- [ ] No functional regressions vs QML panel" \
"phase-2,feature" "Phase 2 - Desktop shell"

create "OS-correct config path resolution" \
"Replace the hardcoded ~/.config/omarchy/... path with :filename.basedir/3 so config lands in the right place per OS.

Acceptance criteria:
- [ ] Config resolves to a sane path on Linux
- [ ] Config resolves to a sane path on Windows
- [ ] Existing config migrated or clearly documented as needing re-entry" \
"phase-2,chore" "Phase 2 - Desktop shell"

# --- Phase 3 ---
create "xterm.js embed in LiveView page" \
"Static embed, no backend wiring yet — just proves xterm.js renders correctly inside the elixir-desktop webview on both platforms.

Acceptance criteria:
- [ ] xterm.js renders and accepts local keystrokes (no backend yet)
- [ ] Confirmed working in both WebView2 and WebKitGTK" \
"phase-3,feature" "Phase 3 - Interactive terminal"

create "Phoenix Channel bridge for terminal I/O" \
"Keystrokes from xterm.js go over a channel to an :ssh_connection shell channel; output streams back to xterm.js.

Acceptance criteria:
- [ ] Interactive shell session usable end-to-end (login, run commands, see output)
- [ ] Latency acceptable for normal typing/scrollback" \
"phase-3,feature" "Phase 3 - Interactive terminal"

create "Bracketed paste mode + PTY resize support" \
"Bracketed paste on by default so multi-line pastes don't get mangled or auto-executed line by line. Window resize propagates as a PTY window-change over the channel.

Acceptance criteria:
- [ ] Multi-line paste lands as a single paste, not executed line-by-line
- [ ] Resizing the window resizes the remote PTY correctly" \
"phase-3,feature" "Phase 3 - Interactive terminal"

create "Cancelable connect with timeout" \
"UI affordance plus :ssh connect timeout wired through end to end; user can abort mid-attempt instead of the client hanging forever on a dead host.

Acceptance criteria:
- [ ] Default timeout configurable, defaults to 10s
- [ ] Cancel button aborts an in-flight connection attempt
- [ ] Timeout surfaces the plain-language 'timed out' error, not a generic failure" \
"phase-3,feature" "Phase 3 - Interactive terminal"

# --- Phase 4 ---
create "Quick-add host parser (user@host:port)" \
"Paste user@host:port directly instead of being forced through a multi-field form for the common case.

Acceptance criteria:
- [ ] Parses user@host, user@host:port, and bare host
- [ ] Falls back to the full form for jump-host/group/auth-method fields" \
"phase-4,feature" "Phase 4 - Host management"

create "~/.ssh/config importer" \
"Parse existing Host blocks into %SSHClient.Host{} on first run, deduped against manually-added hosts.

Acceptance criteria:
- [ ] Host, HostName, User, Port, IdentityFile, ProxyJump parsed
- [ ] Re-running import doesn't duplicate existing hosts" \
"phase-4,feature" "Phase 4 - Host management"

create "Fuzzy search over flat host list" \
"Search-first host list; groups/tags are an optional filter on top, never a required navigation step.

Acceptance criteria:
- [ ] Typing filters the list in real time
- [ ] Works with zero groups configured" \
"phase-4,feature" "Phase 4 - Host management"

create "Per-host auth-order override" \
"Host edit form lets a host specify its own auth method order (e.g. try key, fall back to password) instead of one global setting.

Acceptance criteria:
- [ ] Per-host override persists and is respected on connect
- [ ] Falls back to a sensible global default when unset" \
"phase-4,feature" "Phase 4 - Host management"

# --- Phase 5 ---
create "OS credential store integration: Linux (libsecret)" \
"Passwords/passphrases the user opts to save go into libsecret, never our own config file.

Acceptance criteria:
- [ ] Save, retrieve, delete a credential via libsecret
- [ ] Nothing secret ever written to ssh-client's own JSON/SQLite config" \
"phase-5,feature" "Phase 5 - Credential storage"

create "OS credential store integration: Windows (Credential Manager)" \
"Same as the Linux libsecret issue, targeting Windows Credential Manager.

Acceptance criteria:
- [ ] Save, retrieve, delete a credential via Windows Credential Manager
- [ ] Nothing secret ever written to ssh-client's own JSON/SQLite config" \
"phase-5,feature" "Phase 5 - Credential storage"

create "In-memory-only passphrase cache" \
"Decrypted key passphrases are cached in memory for the session only, never written to disk, cleared on session end.

Acceptance criteria:
- [ ] Passphrase entered once per session, not re-prompted per connection
- [ ] Cache cleared on app quit and verified not persisted anywhere" \
"phase-5,feature" "Phase 5 - Credential storage"

# --- Phase 6 ---
create "Port CPU/RAM/disk/uptime polling to :ssh exec channel, focus-aware" \
"Active/focused host panel polls at the normal interval; backgrounded hosts back off automatically.

Acceptance criteria:
- [ ] Metrics match old shelled-ssh implementation
- [ ] Backgrounded hosts poll less frequently, verified via logs/metrics" \
"phase-6,feature" "Phase 6 - Monitoring & management parity"

create "Port systemd/Docker/PM2 service management panel" \
"Restart/stop with confirmation dialogs — logic unchanged from omarchy-server, transport swapped to :ssh.

Acceptance criteria:
- [ ] Restart/stop works for systemd units, Docker containers, PM2 processes
- [ ] Confirmation dialog required before any destructive action" \
"phase-6,feature" "Phase 6 - Monitoring & management parity"

create "Port log viewer (journalctl/syslog tail)" \
"Same tailing behavior as omarchy-server, over the new :ssh transport.

Acceptance criteria:
- [ ] Tail works and updates live
- [ ] Configurable line count respected" \
"phase-6,feature" "Phase 6 - Monitoring & management parity"

create "Desktop notifications via elixir-desktop" \
"Replace notify-send with elixir-desktop's cross-platform notification API for status transitions (offline/degraded/recovered).

Acceptance criteria:
- [ ] Notifications fire on Linux
- [ ] Notifications fire on Windows" \
"phase-6,feature" "Phase 6 - Monitoring & management parity"

# --- Phase 7 ---
create "Audit TUI for Linux-only assumptions" \
"Check bin/omarchy-server-tui for Linux-only escape sequences or paths and fix for Windows terminal compatibility.

Acceptance criteria:
- [ ] TUI runs correctly in Windows Terminal
- [ ] TUI still runs correctly on Linux terminals" \
"phase-7,chore" "Phase 7 - TUI parity check"

# --- Phase 8 ---
create "GitHub Actions CI" \
"Format check, static analysis, test matrix on ubuntu-latest + windows-latest. See .github/workflows/ci.yml.

Acceptance criteria:
- [ ] CI runs on every PR to main
- [ ] All jobs green on a trivial PR
- [ ] Branch protection on main requires these checks (manual repo settings step)" \
"phase-8,ci" "Phase 8 - Packaging & CI"

create "mix desktop.deploy packaging for Windows installer" \
"Produces a Windows installer artifact from CI.

Acceptance criteria:
- [ ] Installer builds successfully on windows-latest runner
- [ ] Installer installs and launches the app on a clean Windows VM" \
"phase-8,ci" "Phase 8 - Packaging & CI"

create "Linux packaging (AppImage or .deb)" \
"Produces a Linux installer/package artifact from CI.

Acceptance criteria:
- [ ] Package builds successfully on ubuntu-latest runner
- [ ] Package installs and launches on a clean Linux VM/container" \
"phase-8,ci" "Phase 8 - Packaging & CI"

create "README rewrite" \
"Install instructions per OS, auth setup walkthrough, screenshot, no Omarchy-specific language left anywhere.

Acceptance criteria:
- [ ] README covers Windows + Linux install
- [ ] No remaining references to Omarchy/Hyprland/Quickshell
- [ ] Auth setup (key/password/keyboard-interactive) documented" \
"phase-8,docs" "Phase 8 - Packaging & CI"

echo "Done. Created 28 issues across 9 milestones."
