# ssh-client — revamp spec (from omarchy-server)

Name: **ssh-client** (mix.exs app name: `:ssh_client`, module namespace: `SSHClient.*`, repo: `ssh-client`).

## 1. What this is

`omarchy-server` was an Elixir/OTP monitoring daemon + a QML bar widget for the
Omarchy/Hyprland Linux desktop. It was agentless, SSH-only, and had a TUI and
terminal launch. This revamp turns it into a cross-platform (Windows + Linux)
desktop SSH client with the monitoring features kept, built to avoid typical
failure modes: forced accounts, cloud sync by default, sluggish runtime, useless errors,
and silently broken keyboard-interactive auth.

## 2. Non-negotiables

- No account, no forced cloud sync, no telemetry. Fully usable offline, always.
- Credentials never touch our own config file — OS keychain only (Credential Manager /
  libsecret), resolved at connect time.
- Every SSH auth failure maps to a specific, plain-language reason. No generic toasts.
- Idle hosts don't hold open shell channels or eat CPU on a fixed poll no matter what.
- No dependency on an external `ssh` binary — use Erlang's built-in `:ssh` app so it
  works identically on Windows without OpenSSH-for-Windows being installed/on PATH.

## 3. Architecture

| Layer | Old (omarchy-server) | New (ssh-client) |
|---|---|---|
| UI shell | QML + Omarchy/Quickshell bar | Phoenix LiveView in an `elixir-desktop` native window (WebView2 on Windows, WebKitGTK on Linux) |
| Transport | shells out to system `ssh` | Erlang `:ssh` app directly (`:ssh_connection`, `:ssh_sftp`) |
| Interactive terminal | launches external terminal emulator | xterm.js in the LiveView page, bridged over a Phoenix Channel to an `:ssh_connection` shell channel |
| Monitoring | OTP GenServer per host, polls over shelled `ssh` | same GenServer-per-host model, ported to `:ssh` exec channels |
| Service mgmt (systemd/Docker/PM2) | shelled ssh commands | same commands, over `:ssh` exec channel — unaffected by local OS since targets are remote Linux |
| Credentials | none stored (relies on local `~/.ssh` + agent) | OS keychain via platform-specific NIF/port, key-file, or agent — user's choice per host |
| Local storage | `~/.config/omarchy/shell.json` | JSON config at an OS-correct path via `:filename.basedir/3`, or SQLite via Ecto if the host list grows past flat-file usefulness |
| Packaging | Omarchy plugin install | `mix desktop.deploy` (or Burrito) → Windows installer + Linux AppImage/`.deb` |
| TUI | `bin/omarchy-server-tui` | kept, decoupled from any Linux-only escape sequences if not already |

## 4. Feature spec

### 4.1 Auth
- **Key-based**: try identities in order (`id_ed25519`, `id_rsa`, custom path), support
  `ssh-agent`. Passphrase prompted once per session, decrypted key held in memory only.
- **Password**: `:ssh` `password` callback. Stored only if the user opts in, only in the
  OS credential store.
- **Keyboard-interactive**: generic prompt-answer UI wired to `:ssh`'s
  `keyboard-interactive` method — required for cloud VMs (GCP etc.) that don't accept
  plain `password` auth. This is the auth method lightweight clients most often skip,
  and skipping it means silent connection failures on a whole class of hosts.
- Per-host auth order override (e.g. try key, fall back to password).

### 4.2 Connection UX
- Quick-add: paste `user@host:port`, no forced multi-field form.
- Import existing `~/.ssh/config` on first run.
- Configurable connect timeout (default 10s), cancelable mid-attempt.
- Plain-language error mapping: auth rejected / host unreachable / timed out / host key
  changed — each from a specific `:ssh` error reason.
- Host key change: fingerprint diff (old vs new) with explicit accept/reject, never
  silent auto-accept.
- Bracketed paste mode on by default.
- Flat host list with fuzzy search always available, groups/tags optional on top.

### 4.3 Resource discipline
- Interactive shell channel opens only when its tab/session is focused.
- Monitoring uses one non-interactive `exec` channel per host per poll, not a held-open
  shell.
- Poll interval configurable (default 5s), backs off for hosts not currently viewed.

### 4.4 Data model
```elixir
%SSHClient.Host{
  id: String.t(),
  name: String.t(),
  address: String.t(),
  port: pos_integer(),
  user: String.t(),
  auth_method: :key | :password | :agent | :keyboard_interactive,
  identity_file: String.t() | nil,
  jump_host: String.t() | nil,
  group: String.t() | nil,
  last_connected_at: DateTime.t() | nil
}
```
No secret material in this struct — only a reference to the OS credential store entry.

## 5. Issue breakdown (phases → issues)

Each issue below maps to a GitHub issue. Each is worked on its own feature branch, gets
as many commits as it needs, opens a PR to `main`, and only merges once CI is green.
Branch naming: `feat/<issue-number>-<slug>`. Commit style: Conventional Commits
(`feat:`, `fix:`, `chore:`, `test:`, `docs:`), scoped where useful
(`feat(ssh): add keyboard-interactive callback`).

### Phase 0 — Repo & rename
- **#53 Rename project to ssh-client** — `mix.exs` app name (`:ssh_client`), module namespace `SSHClient.*`, `README.md`, repo description, CHANGELOG started fresh with a note pointing back to `omarchy-server` history.
- **#54 Strip Omarchy/QML-specific files** — remove `Panel.qml`, `TerminalView.qml`, Omarchy plugin manifest; keep `lib/`, `test/`, monitoring logic untouched for now.

### Phase 1 — SSH transport core
- **#55 Replace shelled ssh calls with :ssh_connection exec channel** for the monitoring commands (CPU/RAM/disk/uptime polling).
- **#56 Implement :ssh auth callback module** supporting key, password, and keyboard-interactive, selected per host from `auth_method`.
- **#57 Host-key verification & fingerprint diff flow** — reject-by-default on mismatch, surfaced to the UI layer as a distinct event, not swallowed in the connection error.

### Phase 2 — Desktop shell
- **#58 Bootstrap elixir-desktop** — new window, minimal LiveView "hello" page rendering natively on both Windows and Linux dev machines.
- **#59 Port host-list + status UI from QML to LiveView** — same data, new template, no new features yet (parity milestone).
- **#60 OS-correct config path resolution** via `:filename.basedir/3`, replacing the hardcoded `~/.config/omarchy/...` path.

### Phase 3 — Interactive terminal
- **#61 xterm.js embed in LiveView page** — static, no backend wiring yet.
- **#62 Phoenix Channel bridge for terminal I/O** — keystrokes from xterm.js → channel → `:ssh_connection` shell channel; output stream back to xterm.js.
- **#63 Bracketed paste mode + PTY resize support** over the channel.
- **#64 Cancelable connect with timeout** — UI affordance + `:ssh` connect timeout wired through, abort mid-attempt.

### Phase 4 — Host management
- **#65 Quick-add host parser (user@host:port)** for `user@host:port` paste.
- **#66 ~/.ssh/config importer** — parses existing `Host` blocks into `%SSHClient.Host{}` on first run, dedupes against manually-added hosts.
- **#67 Fuzzy search over flat host list** + optional group/tag filter.
- **#68 Per-host auth-order override** in host edit form.

### Phase 5 — Credential storage
- **#69 OS credential store integration: Linux (libsecret)**.
- **#70 OS credential store integration: Windows (Credential Manager)**.
- **#71 In-memory-only passphrase cache** for decrypted keys, cleared on session end.

### Phase 6 — Monitoring & management parity
- **#72 Port CPU/RAM/disk/uptime polling to :ssh exec channel, focus-aware** (active panel = normal interval, backgrounded host = backed-off interval).
- **#73 Port systemd/Docker/PM2 service management panel** (restart/stop + confirmation dialogs) — logic unchanged, transport swapped to `:ssh`.
- **#74 Port log viewer (journalctl/syslog tail)** to new transport.
- **#75 Desktop notifications via elixir-desktop** cross-platform API, replacing `notify-send`.

### Phase 7 — TUI parity check
- **#76 Audit TUI for Linux-only assumptions** (escape sequences, paths) and fix for Windows terminal compatibility.

### Phase 8 — Packaging & CI
- **#77 GitHub Actions CI**: format check, static analysis, test matrix on `ubuntu-latest` + `windows-latest`.
- **#78 mix desktop.deploy packaging for Windows installer**.
- **#79 Linux packaging (AppImage or .deb)**.
- **#80 README rewrite**: install instructions per OS, auth setup, screenshot, no Omarchy-specific language left.

## 6. Git workflow

- One issue → one feature branch → one PR. Branch: `feat/<issue-number>-<short-slug>`.
- Commit as many times as the work naturally splits into — no squash-before-push requirement, but the PR itself merges to `main` via **squash merge** so `main` stays one commit per issue.
- PR description references the issue (`Closes #N`), lists what changed, and notes manual test steps taken.
- Merge requirement: CI green (format, static analysis, tests on both OS runners) + self-review checklist in the PR template.
- No direct pushes to `main`.

## 7. CI Workflow

Jobs on every PR to `main` and every push to `main`:
1. `mix format --check-formatted`
2. `mix credo --strict`
3. `mix test` on a matrix: `ubuntu-latest`, `windows-latest`
4. Build job (push/tag on `main`): produces installer artifacts per OS (`ssh-client-ubuntu-latest`, `ssh-client-windows-latest`), uploaded as workflow artifacts.

## 8. Web Landing Page Prompt

Located in `/web` directory. Zero-build static HTML + Tailwind CSS CDN + daisyUI CDN dark theme.
Monospace font for headers and code/terminal displays, system sans-serif for body.
Clear technical tone, no fluff, no telemetry.
Sections:
1. Hero ("SSH, without the overhead") + terminal mockup
2. Why (offline, key/pw/kbi auth, resource discipline, OS keychain)
3. What it does (management, xterm.js terminal, monitoring, service mgmt, log viewer)
4. Platforms (Windows & Linux)
5. Download (direct releases)
6. Minimal footer (GitHub link, MIT license)
