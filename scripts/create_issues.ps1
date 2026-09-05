$issues = @(
    # --- Phase 0 ---
    @{
        title = "Rename project to ssh-client"
        labels = "phase-0,chore"
        milestone = "Phase 0 - Repo & rename"
        body = @"
mix.exs app name (:ssh_client), module namespace SSHClient.*, README.md, repo description, fresh CHANGELOG with a note pointing back to omarchy-server history.

Acceptance criteria:
- [ ] mix.exs app/module renamed (:ssh_client, SSHClient)
- [ ] All lib/ modules under SSHClient.* namespace
- [ ] README title/description updated
- [ ] CHANGELOG.md started
"@
    },
    @{
        title = "Strip Omarchy/QML-specific files"
        labels = "phase-0,chore"
        milestone = "Phase 0 - Repo & rename"
        body = @"
Remove Panel.qml, TerminalView.qml, Omarchy plugin manifest. Keep lib/, test/, monitoring logic untouched for now — this issue is deletion-only, no new logic.

Acceptance criteria:
- [ ] Panel.qml, TerminalView.qml removed
- [ ] Omarchy plugin manifest removed
- [ ] Existing tests still pass
"@
    },

    # --- Phase 1 ---
    @{
        title = "Replace shelled ssh calls with :ssh_connection exec channel"
        labels = "phase-1,feature"
        milestone = "Phase 1 - SSH transport core"
        body = @"
Port the monitoring commands (CPU/RAM/disk/uptime polling) off shelling to the system ssh binary and onto Erlang's :ssh_connection exec channel directly.

Acceptance criteria:
- [ ] No System.cmd/shell calls to 'ssh' remain in monitoring path
- [ ] Same metrics collected, same GenServer-per-host model
- [ ] Works against a Linux target from both a Linux and Windows dev machine
"@
    },
    @{
        title = "Implement :ssh auth callback module"
        labels = "phase-1,feature"
        milestone = "Phase 1 - SSH transport core"
        body = @"
Support key, password, and keyboard-interactive auth, selected per host from Host.auth_method. Keyboard-interactive matters specifically for cloud VMs (GCP etc.) that reject plain password auth.

Acceptance criteria:
- [ ] Key auth: tries id_ed25519, id_rsa, custom path, in order
- [ ] Password auth via :ssh password callback
- [ ] Keyboard-interactive via generic prompt-answer callback, not hardcoded to a single password field
- [ ] Per-host auth order override respected
"@
    },
    @{
        title = "Host-key verification & fingerprint diff flow"
        labels = "phase-1,feature"
        milestone = "Phase 1 - SSH transport core"
        body = @"
Reject-by-default on host key mismatch. Surface the event distinctly to the UI layer (old fingerprint vs new) rather than folding it into a generic connection error.

Acceptance criteria:
- [ ] First-connect: fingerprint shown, explicit accept required
- [ ] Changed key: diff shown (old vs new), explicit accept/reject, no silent auto-accept
- [ ] Known-hosts persisted correctly
"@
    },

    # --- Phase 2 ---
    @{
        title = "Bootstrap elixir-desktop"
        labels = "phase-2,feature"
        milestone = "Phase 2 - Desktop shell"
        body = @"
New window, minimal LiveView 'hello' page rendering natively on both a Windows and a Linux dev machine.

Acceptance criteria:
- [ ] App launches as a native window on Windows (WebView2)
- [ ] App launches as a native window on Linux (WebKitGTK)
- [ ] Hot-reload/dev workflow documented in README
"@
    },
    @{
        title = "Port host-list + status UI from QML to LiveView"
        labels = "phase-2,feature"
        milestone = "Phase 2 - Desktop shell"
        body = @"
Same data as the old QML panel, new LiveView template. Parity milestone only — no new features here.

Acceptance criteria:
- [ ] Host list renders with live status
- [ ] No functional regressions vs QML panel
"@
    },
    @{
        title = "OS-correct config path resolution"
        labels = "phase-2,chore"
        milestone = "Phase 2 - Desktop shell"
        body = @"
Replace the hardcoded ~/.config/omarchy/... path with :filename.basedir/3 so config lands in the right place per OS.

Acceptance criteria:
- [ ] Config resolves to a sane path on Linux
- [ ] Config resolves to a sane path on Windows
- [ ] Existing config migrated or clearly documented as needing re-entry
"@
    },

    # --- Phase 3 ---
    @{
        title = "xterm.js embed in LiveView page"
        labels = "phase-3,feature"
        milestone = "Phase 3 - Interactive terminal"
        body = @"
Static embed, no backend wiring yet — just proves xterm.js renders correctly inside the elixir-desktop webview on both platforms.

Acceptance criteria:
- [ ] xterm.js renders and accepts local keystrokes (no backend yet)
- [ ] Confirmed working in both WebView2 and WebKitGTK
"@
    },
    @{
        title = "Phoenix Channel bridge for terminal I/O"
        labels = "phase-3,feature"
        milestone = "Phase 3 - Interactive terminal"
        body = @"
Keystrokes from xterm.js go over a channel to an :ssh_connection shell channel; output streams back to xterm.js.

Acceptance criteria:
- [ ] Interactive shell session usable end-to-end (login, run commands, see output)
- [ ] Latency acceptable for normal typing/scrollback
"@
    },
    @{
        title = "Bracketed paste mode + PTY resize support"
        labels = "phase-3,feature"
        milestone = "Phase 3 - Interactive terminal"
        body = @"
Bracketed paste on by default so multi-line pastes don't get mangled or auto-executed line by line. Window resize propagates as a PTY window-change over the channel.

Acceptance criteria:
- [ ] Multi-line paste lands as a single paste, not executed line-by-line
- [ ] Resizing the window resizes the remote PTY correctly
"@
    },
    @{
        title = "Cancelable connect with timeout"
        labels = "phase-3,feature"
        milestone = "Phase 3 - Interactive terminal"
        body = @"
UI affordance plus :ssh connect timeout wired through end to end; user can abort mid-attempt instead of the client hanging forever on a dead host.

Acceptance criteria:
- [ ] Default timeout configurable, defaults to 10s
- [ ] Cancel button aborts an in-flight connection attempt
- [ ] Timeout surfaces the plain-language 'timed out' error, not a generic failure
"@
    },

    # --- Phase 4 ---
    @{
        title = "Quick-add host parser (user@host:port)"
        labels = "phase-4,feature"
        milestone = "Phase 4 - Host management"
        body = @"
Paste user@host:port directly instead of being forced through a multi-field form for the common case.

Acceptance criteria:
- [ ] Parses user@host, user@host:port, and bare host
- [ ] Falls back to the full form for jump-host/group/auth-method fields
"@
    },
    @{
        title = "~/.ssh/config importer"
        labels = "phase-4,feature"
        milestone = "Phase 4 - Host management"
        body = @"
Parse existing Host blocks into %SSHClient.Host{} on first run, deduped against manually-added hosts.

Acceptance criteria:
- [ ] Host, HostName, User, Port, IdentityFile, ProxyJump parsed
- [ ] Re-running import doesn't duplicate existing hosts
"@
    },
    @{
        title = "Fuzzy search over flat host list"
        labels = "phase-4,feature"
        milestone = "Phase 4 - Host management"
        body = @"
Search-first host list; groups/tags are an optional filter on top, never a required navigation step.

Acceptance criteria:
- [ ] Typing filters the list in real time
- [ ] Works with zero groups configured
"@
    },
    @{
        title = "Per-host auth-order override"
        labels = "phase-4,feature"
        milestone = "Phase 4 - Host management"
        body = @"
Host edit form lets a host specify its own auth method order (e.g. try key, fall back to password) instead of one global setting.

Acceptance criteria:
- [ ] Per-host override persists and is respected on connect
- [ ] Falls back to a sensible global default when unset
"@
    },

    # --- Phase 5 ---
    @{
        title = "OS credential store integration: Linux (libsecret)"
        labels = "phase-5,feature"
        milestone = "Phase 5 - Credential storage"
        body = @"
Passwords/passphrases the user opts to save go into libsecret, never our own config file.

Acceptance criteria:
- [ ] Save, retrieve, delete a credential via libsecret
- [ ] Nothing secret ever written to ssh-client's own JSON/SQLite config
"@
    },
    @{
        title = "OS credential store integration: Windows (Credential Manager)"
        labels = "phase-5,feature"
        milestone = "Phase 5 - Credential storage"
        body = @"
Same as the Linux libsecret issue, targeting Windows Credential Manager.

Acceptance criteria:
- [ ] Save, retrieve, delete a credential via Windows Credential Manager
- [ ] Nothing secret ever written to ssh-client's own JSON/SQLite config
"@
    },
    @{
        title = "In-memory-only passphrase cache"
        labels = "phase-5,feature"
        milestone = "Phase 5 - Credential storage"
        body = @"
Decrypted key passphrases are cached in memory for the session only, never written to disk, cleared on session end.

Acceptance criteria:
- [ ] Passphrase entered once per session, not re-prompted per connection
- [ ] Cache cleared on app quit and verified not persisted anywhere
"@
    },

    # --- Phase 6 ---
    @{
        title = "Port CPU/RAM/disk/uptime polling to :ssh exec channel, focus-aware"
        labels = "phase-6,feature"
        milestone = "Phase 6 - Monitoring & management parity"
        body = @"
Active/focused host panel polls at the normal interval; backgrounded hosts back off automatically.

Acceptance criteria:
- [ ] Metrics match old shelled-ssh implementation
- [ ] Backgrounded hosts poll less frequently, verified via logs/metrics
"@
    },
    @{
        title = "Port systemd/Docker/PM2 service management panel"
        labels = "phase-6,feature"
        milestone = "Phase 6 - Monitoring & management parity"
        body = @"
Restart/stop with confirmation dialogs — logic unchanged from omarchy-server, transport swapped to :ssh.

Acceptance criteria:
- [ ] Restart/stop works for systemd units, Docker containers, PM2 processes
- [ ] Confirmation dialog required before any destructive action
"@
    },
    @{
        title = "Port log viewer (journalctl/syslog tail)"
        labels = "phase-6,feature"
        milestone = "Phase 6 - Monitoring & management parity"
        body = @"
Same tailing behavior as omarchy-server, over the new :ssh transport.

Acceptance criteria:
- [ ] Tail works and updates live
- [ ] Configurable line count respected
"@
    },
    @{
        title = "Desktop notifications via elixir-desktop"
        labels = "phase-6,feature"
        milestone = "Phase 6 - Monitoring & management parity"
        body = @"
Replace notify-send with elixir-desktop's cross-platform notification API for status transitions (offline/degraded/recovered).

Acceptance criteria:
- [ ] Notifications fire on Linux
- [ ] Notifications fire on Windows
"@
    },

    # --- Phase 7 ---
    @{
        title = "Audit TUI for Linux-only assumptions"
        labels = "phase-7,chore"
        milestone = "Phase 7 - TUI parity check"
        body = @"
Check bin/omarchy-server-tui for Linux-only escape sequences or paths and fix for Windows terminal compatibility.

Acceptance criteria:
- [ ] TUI runs correctly in Windows Terminal
- [ ] TUI still runs correctly on Linux terminals
"@
    },

    # --- Phase 8 ---
    @{
        title = "GitHub Actions CI"
        labels = "phase-8,ci"
        milestone = "Phase 8 - Packaging & CI"
        body = @"
Format check, static analysis, test matrix on ubuntu-latest + windows-latest. See .github/workflows/ci.yml.

Acceptance criteria:
- [ ] CI runs on every PR to main
- [ ] All jobs green on a trivial PR
- [ ] Branch protection on main requires these checks (manual repo settings step)
"@
    },
    @{
        title = "mix desktop.deploy packaging for Windows installer"
        labels = "phase-8,ci"
        milestone = "Phase 8 - Packaging & CI"
        body = @"
Produces a Windows installer artifact from CI.

Acceptance criteria:
- [ ] Installer builds successfully on windows-latest runner
- [ ] Installer installs and launches the app on a clean Windows VM
"@
    },
    @{
        title = "Linux packaging (AppImage or .deb)"
        labels = "phase-8,ci"
        milestone = "Phase 8 - Packaging & CI"
        body = @"
Produces a Linux installer/package artifact from CI.

Acceptance criteria:
- [ ] Package builds successfully on ubuntu-latest runner
- [ ] Package installs and launches on a clean Linux VM/container
"@
    },
    @{
        title = "README rewrite"
        labels = "phase-8,docs"
        milestone = "Phase 8 - Packaging & CI"
        body = @"
Install instructions per OS, auth setup walkthrough, screenshot, no Omarchy-specific language left anywhere.

Acceptance criteria:
- [ ] README covers Windows + Linux install
- [ ] No remaining references to Omarchy/Hyprland/Quickshell
- [ ] Auth setup (key/password/keyboard-interactive) documented
"@
    }
)

Write-Host "Creating $($issues.Count) issues..."
$count = 0
foreach ($issue in $issues) {
    $count++
    Write-Host "[$count/$($issues.Count)] Creating issue: $($issue.title)"
    gh issue create --repo dineshkorukonda/ssh-client `
        --title $issue.title `
        --body $issue.body `
        --label $issue.labels `
        --milestone $issue.milestone
}
Write-Host "All 28 issues created successfully."
