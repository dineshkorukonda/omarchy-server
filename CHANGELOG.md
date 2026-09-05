# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2026-09-05

### Added
- **Native Erlang/OTP SSH Transport**: Direct `:ssh` engine replacing external binary calls (`:ssh_connection`, `:ssh_sftp`).
- **Authentication**: Native `:ssh` authentication callback supporting `publickey` (`id_ed25519`, `id_rsa`, custom paths), password, ssh-agent, and keyboard-interactive authentication with per-host priority order.
- **Host Key Verification**: Fingerprint diff verification on changed host keys with reject-by-default logic and interactive accept/reject flow.
- **Terminal Engine**: Embedded xterm.js terminal with Phoenix Channel bridge (`terminal:input`, `terminal:output`, `terminal:resize`), PTY resize, and bracketed paste mode.
- **Desktop Window Shell**: Cross-platform desktop window integration via `elixir-desktop` (WebView2 on Windows, WebKitGTK on Linux).
- **Web Interface**: Phoenix LiveView server list (`HostLive`), terminal page (`TerminalLive`), real-time telemetry metrics, and modal dialogs.
- **Host Management**:
  - `user@host:port` quick-add parser.
  - Automatic `~/.ssh/config` importer with host deduplication.
  - In-memory fuzzy search with word boundary ranking over hosts, addresses, and tags.
- **OS Keychain Integration**:
  - Windows Credential Manager integration via PowerShell / native API port.
  - Linux Secret Service (`libsecret`) integration via `secret-tool`.
  - In-memory-only decrypted passphrase cache that clears on session termination.
- **Infrastructure Monitoring & Ops**:
  - Focus-aware polling engine for CPU, RAM, disk, and load average with idle backoff.
  - Remote service manager for `systemd` units, `Docker` containers, and `PM2` processes with confirmation dialogs.
  - Remote log tailing viewer for `journalctl` and system logs.
  - Cross-platform desktop notification router with fallback.
- **TUI Parity**: Portable `ssh-client-tui` terminal user interface compatible with Windows Terminal and Linux consoles.
- **Automated Packaging & Release**:
  - CI test matrix across `windows-latest` and `ubuntu-latest` with Docker OpenSSH integration tests.
  - Automated `mix release` packaging for Windows x64 (`.zip`) and Linux x64 (`.tar.gz`).
  - Automated GitHub Releases on tag push (`v*`).
- **Minimalist Web Landing Page**: Zero-build technical landing site in `/web` with terminal specs, architecture breakdown, install instructions, and changelog.

### Fixed
- Resolved cross-platform socket API fallback for Windows named pipe / TCP vs Linux Unix domain sockets.
- Corrected host key verification callback to accept character list hostnames from Erlang `:ssh`.
- Stripped UTF-8 BOM characters across codebase for strict POSIX and Elixir compiler compatibility.
- Fine-tuned 2-character word boundary matching in fuzzy search engine.

### Changed
- Project renamed from `omarchy-server` to `ssh-client` (`:ssh_client` app, `SSHClient.*` namespace).
- Stripped Omarchy/QML desktop bar dependencies in favor of cross-platform LiveView + `elixir-desktop`.

---

## [0.1.0] - Prior History (`omarchy-server`)
- Historical releases originated as `omarchy-server`, an agentless SSH monitoring daemon and QML bar widget for Omarchy/Hyprland on Linux.
- Included Unix domain socket API, multi-target monitoring, init-system inspection (systemd, docker, pm2), and PTY-backed terminal daemon.
