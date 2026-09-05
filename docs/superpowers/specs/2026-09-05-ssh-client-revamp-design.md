# ssh-client Revamp — Design Document

## 1. Executive Summary

This document specifies the architectural transformation of `omarchy-server` (originally an Elixir/OTP monitoring daemon + Linux QML bar widget) into **`ssh-client`**, a cross-platform (Windows + Linux) desktop SSH client with agentless remote host monitoring, interactive terminal sessions, credential management, and service control.

The system is built on Elixir/OTP, Erlang's native `:ssh` application, and Phoenix LiveView inside an `elixir-desktop` native window (WebView2 on Windows, WebKitGTK on Linux).

## 2. Core Principles & Non-Negotiables

1. **Zero Forced Cloud / Zero Accounts / Zero Telemetry**: Operates completely offline. No accounts, no cloud sync, no tracking.
2. **Credential Hygiene**: Secrets (passwords, private key passphrases) never persist in application config files. They resolve exclusively via the OS credential store (Windows Credential Manager / Linux libsecret) at connection time. Passphrases for decrypted private keys are kept in-memory only and cleared on session exit.
3. **Deterministic, Plain-Language SSH Diagnostics**: Every SSH authentication failure, network error, or host key anomaly maps to an actionable, unambiguous message (e.g. "Public key rejected", "Host key changed - fingerprint mismatch", "Connection timed out after 10s"). No generic "Connection failed" toasts.
4. **Resource Discipline**:
   - Interactive shell channels exist only while their tab/session is actively rendered or focused.
   - Host monitoring polls through ephemeral, single-shot `:ssh_connection` `exec` channels, not persistent shell processes.
   - Polling frequency dynamically backs off for hosts not actively being viewed in the UI.
5. **No External SSH Binary Dependency**: All SSH transport uses Erlang/OTP's `:ssh` suite directly, ensuring seamless behavior on Windows without requiring OpenSSH-for-Windows in `%PATH%`.

## 3. Architecture & Layer Comparison

| Layer | Previous (`omarchy-server`) | New (`ssh-client`) |
|---|---|---|
| **App Namespace** | `OmarchyServer.*` | `SSHClient.*` (app: `:ssh_client`) |
| **Window & UI Shell** | QML + Hyprland/Quickshell | Phoenix LiveView inside `elixir-desktop` (WebView2 on Windows, WebKitGTK on Linux) |
| **SSH Transport** | Shells out via `System.cmd("ssh", ...)` | OTP `:ssh` application (`:ssh_connection`, `:ssh_sftp`) |
| **Terminal Emulator** | Spawns external terminal emulator | Embedded xterm.js in LiveView, bridged via Phoenix Channel to OTP `:ssh_connection` shell channel |
| **Monitoring Daemon** | GenServer per host running shelled commands | GenServer per host using `:ssh_connection` exec channels |
| **Service Control** | System commands via shelled SSH | Remote commands executed via `:ssh_connection` exec channels |
| **Credentials** | Unmanaged (system default paths) | OS Credential Store (Windows Credential Manager / Linux libsecret) + Session RAM cache |
| **Configuration** | Hardcoded `~/.config/omarchy/shell.json` | OS-standard directory via `:filename.basedir/3` (AppData on Windows, `.config` on Linux) |
| **Packaging** | Omarchy plugin manifest | `mix desktop.deploy` / Burrito: Windows installer (`.exe`) + Linux AppImage / `.deb` |
| **TUI** | `bin/omarchy-server-tui` | Retained and audited for cross-platform terminal compatibility |

## 4. Subsystems & Component Design

### 4.1 Data Models (`SSHClient.Host`)

```elixir
defmodule SSHClient.Host do
  @enforce_keys [:id, :name, :address, :port, :user]
  defstruct [
    :id,
    :name,
    :address,
    :port,
    :user,
    auth_method: :key, # :key | :password | :agent | :keyboard_interactive
    identity_file: nil,
    jump_host: nil,
    group: nil,
    auth_order: [:key, :password, :keyboard_interactive],
    connect_timeout: 10_000,
    poll_interval: 5_000,
    last_connected_at: nil
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    address: String.t(),
    port: pos_integer(),
    user: String.t(),
    auth_method: :key | :password | :agent | :keyboard_interactive,
    identity_file: Path.t() | nil,
    jump_host: String.t() | nil,
    group: String.t() | nil,
    auth_order: list(atom()),
    connect_timeout: pos_integer(),
    poll_interval: pos_integer(),
    last_connected_at: DateTime.t() | nil
  }
end
```

### 4.2 SSH Connection & Authentication Subsystem

- **`SSHClient.SSH.Connection`**: Manages the connection lifecycle to a remote host using `:ssh.connect/3`.
  - Supports configurable timeouts with explicit cancellation mid-flight.
  - Implements custom `:ssh` callback handlers for:
    - **Public Key**: Queries identities (`~/.ssh/id_ed25519`, `~/.ssh/id_rsa`, custom configured paths) or queries `ssh-agent`.
    - **Password**: Queries password from in-memory cache or OS credential store.
    - **Keyboard-Interactive**: Handles arbitrary prompt/response sequences (critical for cloud VMs like GCP/AWS/Azure).
- **`SSHClient.SSH.HostKeyVerifier`**:
  - Validates remote host public key against `known_hosts`.
  - Mismatched host keys trigger an explicit fingerprint comparison event (Old SHA256 vs New SHA256) sent to the UI.
  - Disallows automatic silent acceptance of changed keys.

### 4.3 Interactive Terminal Subsystem

- **Frontend**: xterm.js bundled and initialized in a LiveView hook. Supports bracketed paste mode by default, PTY window resize event forwarding, and clipboard integration.
- **Transport Bridge**:
  - `SSHClientWeb.TerminalChannel`: Phoenix Channel receiving binary input and resize payloads (`cols`, `rows`, `xpix`, `ypix`).
  - `SSHClient.SSH.ShellSession`: An OTP process holding the open `:ssh_connection` shell channel with a pseudo-terminal (PTY) allocated (`:ssh_connection.ptty_alloc/4`).
  - Terminal output is streamed as binary frames directly down the channel to xterm.js.
  - Lifecycle: When the terminal tab closes or the window unloads, the shell channel and associated OTP worker immediately terminate.

### 4.4 Agentless Host Monitoring Subsystem

- **`SSHClient.Monitoring.ServerWorker`**:
  - Maintains state for a single configured host.
  - Periodic polling executes single-shot `exec` commands:
    - CPU: `/proc/stat` or `top -bn1`
    - Memory: `/proc/meminfo` or `free -b`
    - Disk: `df -k`
    - Uptime: `/proc/uptime`
  - **Focus-Aware Polling**: When a host's detail view is open in LiveView, polls at the configured frequency (e.g. 5s). When backgrounded, polls on a backed-off frequency (e.g. 30s) or halts if the host is inactive.

### 4.5 Service & Process Management Subsystem

- **`SSHClient.Services.Manager`**:
  - Detects remote init system (`systemd`, `docker`, `pm2`, `openrc`, `sysvinit`).
  - Issues actions (`restart`, `stop`, `start`) over `:ssh_connection` exec channels.
  - Requires explicit confirmation via modal dialog before issuing destructive commands.
  - Streams logs (`journalctl -u <unit> -n <lines> -f`, Docker logs) via exec channel.

### 4.6 Credential Storage Subsystem

- **`SSHClient.Credentials.Vault`**:
  - Abstract behaviour for credential retrieval, storage, and deletion.
  - Platform implementations:
    - **Linux**: `SSHClient.Credentials.Libsecret` using `libsecret-1` / SecretService.
    - **Windows**: `SSHClient.Credentials.CredentialManager` using Win32 `CredReadW` / `CredWriteW`.
  - Passphrase Cache: `SSHClient.Credentials.SessionCache` (in-memory OTP agent, non-persisted, wiped on application termination).

### 4.7 Config & Host Management Subsystem

- **`SSHClient.Config.Storage`**:
  - Resolves OS configuration paths via `:filename.basedir(:user_config, "ssh-client")`.
  - Serializes host configurations without credentials.
- **`SSHClient.Config.SSHConfigImporter`**:
  - Parses OpenSSH `~/.ssh/config` files into `%SSHClient.Host{}` entries.
  - Handles `Host`, `HostName`, `User`, `Port`, `IdentityFile`, `ProxyJump`.
  - Dedupes entries against existing host records.
- **`SSHClient.Config.QuickAdd`**:
  - Parses `user@host:port` format strings into valid `%SSHClient.Host{}` initial structs.

## 5. Phased Roadmap (Mapped to GitHub Issues)

- **Phase 0 — Repo & rename**:
  - #53 Rename project to ssh-client
  - #54 Strip Omarchy/QML-specific files
- **Phase 1 — SSH transport core**:
  - #55 Replace shelled ssh calls with :ssh_connection exec channel
  - #56 Implement :ssh auth callback module
  - #57 Host-key verification & fingerprint diff flow
- **Phase 2 — Desktop shell**:
  - #58 Bootstrap elixir-desktop
  - #59 Port host-list + status UI from QML to LiveView
  - #60 OS-correct config path resolution
- **Phase 3 — Interactive terminal**:
  - #61 xterm.js embed in LiveView page
  - #62 Phoenix Channel bridge for terminal I/O
  - #63 Bracketed paste mode + PTY resize support
  - #64 Cancelable connect with timeout
- **Phase 4 — Host management**:
  - #65 Quick-add host parser (user@host:port)
  - #66 ~/.ssh/config importer
  - #67 Fuzzy search over flat host list
  - #68 Per-host auth-order override
- **Phase 5 — Credential storage**:
  - #69 OS credential store integration: Linux (libsecret)
  - #70 OS credential store integration: Windows (Credential Manager)
  - #71 In-memory-only passphrase cache
- **Phase 6 — Monitoring & management parity**:
  - #72 Port CPU/RAM/disk/uptime polling to :ssh exec channel, focus-aware
  - #73 Port systemd/Docker/PM2 service management panel
  - #74 Port log viewer (journalctl/syslog tail)
  - #75 Desktop notifications via elixir-desktop
- **Phase 7 — TUI parity check**:
  - #76 Audit TUI for Linux-only assumptions
- **Phase 8 — Packaging & CI**:
  - #77 GitHub Actions CI
  - #78 mix desktop.deploy packaging for Windows installer
  - #79 Linux packaging (AppImage or .deb)
  - #80 README rewrite

## 6. Testing & Quality Strategy

1. **Unit Testing**: ExUnit tests for host parsers, quick-add grammar, SSH config import, metrics parsing, and credential interfaces.
2. **Integration Testing**: Docker-based mock SSH daemon fixture testing key authentication, password authentication, and command execution.
3. **Cross-Platform Verification**: GitHub Actions matrix executing formatting, Credo static analysis, and ExUnit test suite on both `ubuntu-latest` and `windows-latest`.
